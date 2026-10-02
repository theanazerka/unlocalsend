#import "LSTransport.h"
#import "LSTLSIdentity.h"
#import "mbedtls/ecp.h"
#import <sys/socket.h>
#import <netdb.h>
#import <unistd.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/select.h>
#import "mbedtls/platform_time.h"
#import <time.h>
#import "mbedtls/ctr_drbg.h"
#import "mbedtls/entropy.h"
#import "mbedtls/net_sockets.h"
#import "mbedtls/sha256.h"
#import "mbedtls/ssl.h"
#import "mbedtls/x509_crt.h"
#import "mbedtls/pk.h"
#import "mbedtls/rsa.h"
#import "mbedtls/oid.h"
#import "mbedtls/error.h"

static NSError *LSError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"LocalSendTLS" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static int LSCreateClientIdentity(mbedtls_ctr_drbg_context *rng,
                                  mbedtls_pk_context *key,
                                  mbedtls_x509_crt *cert) {
    mbedtls_x509write_cert writer;
    mbedtls_x509write_crt_init(&writer);
    int ret = mbedtls_pk_setup(key, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
    if (ret == 0) ret = mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1, mbedtls_pk_ec(*key), mbedtls_ctr_drbg_random, rng);
    if (ret != 0) goto cleanup;

    mbedtls_x509write_crt_set_version(&writer, MBEDTLS_X509_CRT_VERSION_3);
    mbedtls_x509write_crt_set_md_alg(&writer, MBEDTLS_MD_SHA256);
    mbedtls_x509write_crt_set_subject_key(&writer, key);
    mbedtls_x509write_crt_set_issuer_key(&writer, key);
    ret = mbedtls_x509write_crt_set_subject_name(&writer, "CN=LocalSend 6");
    if (ret == 0) ret = mbedtls_x509write_crt_set_issuer_name(&writer, "CN=LocalSend 6");
    unsigned char serialBytes[16];
    if (ret == 0) ret = mbedtls_ctr_drbg_random(rng, serialBytes, sizeof(serialBytes));
    serialBytes[0] &= 0x7f;
    mbedtls_mpi serial; mbedtls_mpi_init(&serial);
    if (ret == 0) ret = mbedtls_mpi_read_binary(&serial, serialBytes, sizeof(serialBytes));
    if (ret == 0) ret = mbedtls_x509write_crt_set_serial(&writer, &serial);
    mbedtls_mpi_free(&serial);
    time_t now = time(NULL); struct tm before, after;
    gmtime_r(&now, &before); gmtime_r(&now, &after);
    before.tm_year -= 1; after.tm_year += 10;
    char notBefore[16], notAfter[16];
    strftime(notBefore, sizeof(notBefore), "%Y%m%d%H%M%S", &before);
    strftime(notAfter, sizeof(notAfter), "%Y%m%d%H%M%S", &after);
    if (ret == 0) ret = mbedtls_x509write_crt_set_validity(&writer, notBefore, notAfter);
    if (ret == 0) ret = mbedtls_x509write_crt_set_basic_constraints(&writer, 1, 0);
    if (ret == 0) ret = mbedtls_x509write_crt_set_key_usage(&writer, MBEDTLS_X509_KU_DIGITAL_SIGNATURE);
    static unsigned char clientAuthOID[] = {0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x02};
    static unsigned char serverAuthOID[] = {0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x01};
    mbedtls_asn1_sequence serverAuth; memset(&serverAuth, 0, sizeof(serverAuth));
    serverAuth.buf.tag=MBEDTLS_ASN1_OID; serverAuth.buf.p=serverAuthOID; serverAuth.buf.len=sizeof(serverAuthOID);
    mbedtls_asn1_sequence clientAuth; memset(&clientAuth, 0, sizeof(clientAuth)); clientAuth.next=&serverAuth;
    clientAuth.buf.tag = MBEDTLS_ASN1_OID; clientAuth.buf.p = clientAuthOID; clientAuth.buf.len = sizeof(clientAuthOID);
    if (ret == 0) ret = mbedtls_x509write_crt_set_ext_key_usage(&writer, &clientAuth);
    unsigned char pem[8192];
    if (ret == 0) ret = mbedtls_x509write_crt_pem(&writer, pem, sizeof(pem), mbedtls_ctr_drbg_random, rng);
    if (ret == 0) ret = mbedtls_x509_crt_parse(cert, pem, strlen((char *)pem) + 1);
cleanup:
    mbedtls_x509write_crt_free(&writer);
    return ret;
}

static NSData *LSCachedCertificate;
static NSData *LSCachedPrivateKey;
static int LSIdentityResult;
int LSSetupLocalIdentity(mbedtls_ctr_drbg_context *rng, mbedtls_pk_context *key, mbedtls_x509_crt *cert) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *library=[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES) objectAtIndex:0];
        NSString *folder=[library stringByAppendingPathComponent:@"LocalSendIdentity"];
        NSString *certPath=[folder stringByAppendingPathComponent:@"certificate.der"];
        NSString *keyPath=[folder stringByAppendingPathComponent:@"private.pem"];
#if defined(LS_TEST_EXPORT_CLIENT_CERT)
        // Tests use an isolated ephemeral identity, without touching user data.
        folder=nil; certPath=nil; keyPath=nil;
#endif
        NSData *savedCert=certPath?[NSData dataWithContentsOfFile:certPath]:nil;
        NSData *savedKey=keyPath?[NSData dataWithContentsOfFile:keyPath]:nil;
        mbedtls_pk_context localKey; mbedtls_pk_init(&localKey);
        mbedtls_x509_crt localCert; mbedtls_x509_crt_init(&localCert);
        int result=-1;
        if(savedKey.length && savedCert.length){
            result=mbedtls_pk_parse_key(&localKey,savedKey.bytes,savedKey.length,NULL,0,mbedtls_ctr_drbg_random,rng);
            if(result==0)result=mbedtls_x509_crt_parse(&localCert,savedCert.bytes,savedCert.length);
            if(result==0)result=mbedtls_pk_check_pair(&localCert.pk,&localKey,mbedtls_ctr_drbg_random,rng);
        }
        if(result!=0){
            mbedtls_pk_free(&localKey);mbedtls_pk_init(&localKey);mbedtls_x509_crt_free(&localCert);mbedtls_x509_crt_init(&localCert);
            result=LSCreateClientIdentity(rng,&localKey,&localCert);
            unsigned char pem[8192]; if(result==0)result=mbedtls_pk_write_key_pem(&localKey,pem,sizeof(pem));
            if(result==0){
                savedKey=[NSData dataWithBytes:pem length:strlen((char *)pem)+1];
                savedCert=[NSData dataWithBytes:localCert.raw.p length:localCert.raw.len];
                if(folder){ [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
                    [savedKey writeToFile:keyPath atomically:YES]; [savedCert writeToFile:certPath atomically:YES];
                    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:keyPath error:nil]; }
            }
        }
        LSIdentityResult=result;
        if(result==0){LSCachedPrivateKey=savedKey;LSCachedCertificate=savedCert;}
        mbedtls_pk_free(&localKey);mbedtls_x509_crt_free(&localCert);
    });
    int ret=LSIdentityResult;
    if(ret==0)ret=mbedtls_pk_parse_key(key,LSCachedPrivateKey.bytes,LSCachedPrivateKey.length,NULL,0,mbedtls_ctr_drbg_random,rng);
    if(ret==0)ret=mbedtls_x509_crt_parse(cert,LSCachedCertificate.bytes,LSCachedCertificate.length);
#if defined(LS_TEST_EXPORT_CLIENT_CERT)
    const char *path=getenv("LS_TEST_CLIENT_CERT");
    if(ret==0 && path && ![LSCachedCertificate writeToFile:[NSString stringWithUTF8String:path] atomically:YES])ret=MBEDTLS_ERR_X509_FILE_IO_ERROR;
#endif
    return ret;
}
NSString *LSLocalFingerprint(void) {
    if(!LSCachedCertificate)return @"";
    unsigned char digest[32]; if(mbedtls_sha256(LSCachedCertificate.bytes,LSCachedCertificate.length,digest,0)!=0)return @"";
    NSMutableString *s=[NSMutableString string];for(NSUInteger i=0;i<32;i++)[s appendFormat:@"%02X",digest[i]];return s;
}

static NSString *LSErrorText(int code) {
    char buffer[256]; mbedtls_strerror(code, buffer, sizeof(buffer));
    return [NSString stringWithUTF8String:buffer];
}

static NSString *LSNormalizeFingerprint(NSString *value) {
    NSString *plain = [[value stringByReplacingOccurrencesOfString:@":" withString:@""] uppercaseString];
    return [[plain componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
}

static int LSVerifyPinnedServer(void *context, mbedtls_x509_crt *cert,
                                int depth, uint32_t *flags) {
    if (depth != 0) return 0;
    NSString *expected = LSNormalizeFingerprint((__bridge NSString *)context);
    if (!expected.length) { *flags = 0; return 0; }
    unsigned char digest[32];
    if (mbedtls_sha256(cert->raw.p, cert->raw.len, digest, 0) != 0) return MBEDTLS_ERR_X509_CERT_VERIFY_FAILED;
    NSMutableString *actual = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [actual appendFormat:@"%02X", digest[i]];
    if (![actual isEqualToString:expected]) return MBEDTLS_ERR_X509_CERT_VERIFY_FAILED;
    *flags = 0;
    return 0;
}

static int LSConnect(mbedtls_net_context *net,NSString *host,NSString *port) {
    struct addrinfo hints,*addresses=NULL;memset(&hints,0,sizeof(hints));hints.ai_socktype=SOCK_STREAM;hints.ai_family=AF_UNSPEC;hints.ai_flags=AI_NUMERICHOST;
    if(getaddrinfo(host.UTF8String,port.UTF8String,&hints,&addresses)!=0)return MBEDTLS_ERR_NET_UNKNOWN_HOST;
    int result=MBEDTLS_ERR_NET_CONNECT_FAILED;mbedtls_ms_time_t deadline=mbedtls_ms_time()+8000;
    for(struct addrinfo *a=addresses;a;a=a->ai_next){
        int fd=socket(a->ai_family,a->ai_socktype,a->ai_protocol);if(fd<0)continue;int flags=fcntl(fd,F_GETFL,0);fcntl(fd,F_SETFL,flags|O_NONBLOCK);
        int connected=connect(fd,a->ai_addr,a->ai_addrlen);
        if(connected!=0 && errno==EINPROGRESS){fd_set set;FD_ZERO(&set);FD_SET(fd,&set);int64_t left=MAX(0,deadline-mbedtls_ms_time());struct timeval wait={left/1000,(left%1000)*1000};int status=select(fd+1,NULL,&set,NULL,&wait);int error=0;socklen_t size=sizeof(error);connected=status>0 && getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size)==0 && error==0?0:-1;}
        if(connected==0){fcntl(fd,F_SETFL,flags);int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));net->fd=fd;result=0;break;}close(fd);if(mbedtls_ms_time()>=deadline)break;
    }
    freeaddrinfo(addresses);return result;
}

NSData *LSHTTPSRequest(NSURLRequest *request, NSString *fingerprint, NSURLResponse **response, NSError **error) {
    return LSHTTPSRequestWithProgress(request,fingerprint,response,error,nil);
}
NSData *LSHTTPSRequestWithProgress(NSURLRequest *request, NSString *fingerprint,
                       NSURLResponse **response, NSError **error, void (^progress)(NSString *, double)) {
    mbedtls_entropy_context entropy; mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_context rng; mbedtls_ctr_drbg_init(&rng);
    mbedtls_pk_context key; mbedtls_pk_init(&key);
    mbedtls_x509_crt clientCert; mbedtls_x509_crt_init(&clientCert);
    mbedtls_ssl_config config; mbedtls_ssl_config_init(&config);
    mbedtls_ssl_context ssl; mbedtls_ssl_init(&ssl);
    mbedtls_net_context socket; mbedtls_net_init(&socket);
    int ret = mbedtls_ctr_drbg_seed(&rng, mbedtls_entropy_func, &entropy,
                                    (const unsigned char *)"LocalSend iOS", 13);
    if (ret == 0) ret = LSSetupLocalIdentity(&rng, &key, &clientCert);
    if (ret == 0) ret = mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_CLIENT,
                          MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret == 0) {
        mbedtls_ssl_conf_min_tls_version(&config, MBEDTLS_SSL_VERSION_TLS1_2);
        mbedtls_ssl_conf_max_tls_version(&config, MBEDTLS_SSL_VERSION_TLS1_3);
        mbedtls_ssl_conf_authmode(&config, MBEDTLS_SSL_VERIFY_REQUIRED);
        // LocalSend presents a self-signed certificate. Supply a non-empty trust
        // anchor so Mbed TLS runs the verifier; the callback accepts only the
        // configured SHA-256 leaf pin (or TOFU when no pin was provided).
        mbedtls_ssl_conf_ca_chain(&config, &clientCert, NULL);
        mbedtls_ssl_conf_verify(&config, LSVerifyPinnedServer, (__bridge void *)LSNormalizeFingerprint(fingerprint ?: @""));
        mbedtls_ssl_conf_rng(&config, mbedtls_ctr_drbg_random, &rng);
        ret = mbedtls_ssl_conf_own_cert(&config, &clientCert, &key);
    }
    if (ret == 0) ret = mbedtls_ssl_setup(&ssl, &config);
    NSString *host = request.URL.host; NSString *port = [request.URL.port stringValue] ?: @"53317";
    if (ret == 0) ret = mbedtls_ssl_set_hostname(&ssl, host.UTF8String);
    if (ret == 0) ret = LSConnect(&socket,host,port);
    if (ret == 0) {
        struct timeval timeout = {10, 0};
        setsockopt(socket.fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(socket.fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        mbedtls_ssl_set_bio(&ssl, &socket, mbedtls_net_send, mbedtls_net_recv, NULL);
        do { ret = mbedtls_ssl_handshake(&ssl); } while (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE);
    }
    if (ret == 0) {
        struct timeval timeout={(int)MAX(10,request.timeoutInterval),0}; setsockopt(socket.fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        if (!mbedtls_ssl_get_peer_cert(&ssl)) ret = MBEDTLS_ERR_X509_INVALID_FORMAT;
    }
    NSMutableData *result = [NSMutableData data];
    if (ret == 0) {
        NSString *path = request.URL.path.length ? request.URL.path : @"/";
        if (request.URL.query.length) path = [path stringByAppendingFormat:@"?%@", request.URL.query];
        NSMutableString *head = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\nHost: %@:%@\r\nConnection: close\r\n", request.HTTPMethod ?: @"GET", path, host, port];
        NSDictionary *headers = request.allHTTPHeaderFields;
        for (NSString *name in headers) [head appendFormat:@"%@: %@\r\n", name, [headers objectForKey:name]];
        NSData *body = request.HTTPBody ?: [NSData data];
        [head appendFormat:@"Content-Length: %lu\r\n\r\n", (unsigned long)body.length];
        NSMutableData *outgoing = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; [outgoing appendData:body];
        size_t offset = 0; mbedtls_ms_time_t lastProgress=0;
        while (ret == 0 && offset < outgoing.length) {
            int sent = mbedtls_ssl_write(&ssl, (const unsigned char *)outgoing.bytes + offset, MIN((size_t)16384,outgoing.length - offset));
            if (sent > 0) { offset += (size_t)sent; mbedtls_ms_time_t now=mbedtls_ms_time();if(progress && (now-lastProgress>100 || offset==outgoing.length)){progress(@"upload",(double)offset/outgoing.length);lastProgress=now;} }
            else if (sent != MBEDTLS_ERR_SSL_WANT_READ && sent != MBEDTLS_ERR_SSL_WANT_WRITE) ret = sent;
        }
    }
    if (ret == 0) {
        if(progress)progress(@"waiting",1);
        unsigned char buffer[8192]; NSMutableData *wire = [NSMutableData data]; NSInteger expected = -1; NSRange boundary = NSMakeRange(NSNotFound, 0);
        for (;;) {
            int n = mbedtls_ssl_read(&ssl, buffer, sizeof(buffer));
            if (n > 0) {
                [wire appendBytes:buffer length:(NSUInteger)n];
                if (boundary.location == NSNotFound) {
                    NSRange marker = [wire rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0, wire.length)];
                    if (marker.location != NSNotFound) {
                        boundary = NSMakeRange(marker.location + marker.length, 0);
                        NSString *header = [[NSString alloc] initWithData:[wire subdataWithRange:NSMakeRange(0,marker.location)] encoding:NSISOLatin1StringEncoding];
                        for (NSString *line in [header componentsSeparatedByString:@"\r\n"]) if ([[line lowercaseString] hasPrefix:@"content-length:"]) expected = [[line substringFromIndex:15] integerValue];
                    }
                }
                if (boundary.location != NSNotFound && expected >= 0 && wire.length >= boundary.location + (NSUInteger)expected) break;
            } else if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
            else if (n == 0 || n == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) break;
            else { ret = n; break; }
        }
        NSRange marker = [wire rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0,wire.length)];
        if (ret == 0 && marker.location != NSNotFound) {
            NSString *header = [[NSString alloc] initWithData:[wire subdataWithRange:NSMakeRange(0,marker.location)] encoding:NSISOLatin1StringEncoding];
            NSArray *lines = [header componentsSeparatedByString:@"\r\n"]; NSArray *parts = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
            NSInteger status = parts.count > 1 ? [[parts objectAtIndex:1] integerValue] : 0; NSMutableDictionary *fields = [NSMutableDictionary dictionary];
            for (NSUInteger i = 1; i < lines.count; i++) { NSRange colon = [[lines objectAtIndex:i] rangeOfString:@":"]; if (colon.location != NSNotFound) fields[[[lines objectAtIndex:i] substringToIndex:colon.location]] = [[[lines objectAtIndex:i] substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; }
            if (response) *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:fields];
            [result appendData:[wire subdataWithRange:NSMakeRange(marker.location+marker.length,wire.length-marker.location-marker.length)]];
        } else if (ret == 0) ret = MBEDTLS_ERR_SSL_BAD_INPUT_DATA;
    }
    if (ret != 0 && error) *error = LSError(ret, [NSString stringWithFormat:@"TLS/HTTP %@", LSErrorText(ret)]);
    if (socket.fd >= 0) mbedtls_net_free(&socket);
    mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&config); mbedtls_x509_crt_free(&clientCert);
    mbedtls_pk_free(&key); mbedtls_ctr_drbg_free(&rng); mbedtls_entropy_free(&entropy);
    return ret == 0 ? result : nil;
}
