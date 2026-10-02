#import "LSLocalization.h"
#import "LSReceiver.h"
#import "LSTLSIdentity.h"
#import "mbedtls/ssl.h"
#import "mbedtls/entropy.h"
#import "mbedtls/net_sockets.h"
#import "mbedtls/sha256.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>

// Streaming HTTP body reader supports both Content-Length and chunked uploads.
@interface LSBody : NSObject
@property (nonatomic, assign) mbedtls_ssl_context *ssl;
@property (nonatomic, assign) int socket;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, assign) int64_t remaining;
@property (nonatomic, assign) uint64_t chunkRemaining;
@property (nonatomic, assign) BOOL chunked;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL failed;
- (NSData *)next;
- (NSString *)line;
@end
@implementation LSBody
- (BOOL)fill { unsigned char b[16384]; int n=mbedtls_ssl_read(self.ssl,b,sizeof(b)); if(n<=0){self.failed=YES;return NO;}[self.buffer appendBytes:b length:n];return YES; }
- (NSData *)take:(NSUInteger)count { NSData *d=[self.buffer subdataWithRange:NSMakeRange(0,count)]; [self.buffer replaceBytesInRange:NSMakeRange(0,count) withBytes:NULL length:0];return d; }
- (NSString *)line { for(;;){NSRange r=[self.buffer rangeOfData:[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:NSMakeRange(0,self.buffer.length)]; if(r.location!=NSNotFound){NSString *s=[[NSString alloc] initWithData:[self take:r.location] encoding:NSASCIIStringEncoding];[self take:2];return s;}if(self.buffer.length>16384 || ![self fill]){self.failed=YES;return nil;}} }
- (NSData *)next {
    if(self.finished||self.failed)return nil;
    if(self.chunked){
        if(!self.chunkRemaining){NSString *line=[self line]; if(!line)return nil; NSString *hex=[[line componentsSeparatedByString:@";"] objectAtIndex:0]; const char *c=hex.UTF8String; char *end=NULL;errno=0;uint64_t size=strtoull(c,&end,16);if(!hex.length||hex.length>16||errno||*end||[hex rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location!=NSNotFound){self.failed=YES;return nil;}self.chunkRemaining=size;
            if(!size){NSUInteger count=0;for(;;){NSString *trailer=[self line];if(!trailer)return nil;if(!trailer.length)break;count+=trailer.length;if(count>16384){self.failed=YES;return nil;}}self.finished=YES;return nil;}
        }
        if(!self.buffer.length && ![self fill])return nil;
        NSData *data=[self take:(NSUInteger)MIN((uint64_t)self.buffer.length,self.chunkRemaining)];self.chunkRemaining-=data.length;
        if(!self.chunkRemaining){while(self.buffer.length<2)if(![self fill])return nil;NSData *crlf=[self take:2];if(![crlf isEqualToData:[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding]]){self.failed=YES;return nil;}}
        return data;
    }
    if(self.remaining==0){self.finished=YES;return nil;}
    if(!self.buffer.length && ![self fill])return nil;
    NSData *data=[self take:(NSUInteger)MIN((int64_t)self.buffer.length,self.remaining)];self.remaining-=data.length;return data;
}
@end
static int LSAllowClient(void *ctx,mbedtls_x509_crt *crt,int depth,uint32_t *flags){*flags=0;return 0;}
static BOOL LSReply(mbedtls_ssl_context *ssl,NSInteger status,id object){
    NSData *body=object?[NSJSONSerialization dataWithJSONObject:object options:0 error:nil]:[NSData data];
    NSString *head=[NSString stringWithFormat:@"HTTP/1.1 %ld LocalSend\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",(long)status,(unsigned long)body.length];NSMutableData *wire=[[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];[wire appendData:body];
    NSUInteger offset=0;while(offset<wire.length){int n=mbedtls_ssl_write(ssl,(const unsigned char *)wire.bytes+offset,MIN((NSUInteger)16384,wire.length-offset));if(n<=0)return NO;offset+=n;}return YES;
}
@interface LSReceiver ()
@property (atomic, assign) BOOL ready;
@property (atomic, assign) BOOL running;
@property (nonatomic, assign) int listener;
@property (nonatomic, strong) NSMutableSet *clients;
@property (nonatomic, strong) NSMutableSet *uploadSockets;
@property (nonatomic, strong) NSMutableDictionary *session;
@property (nonatomic, strong) NSCondition *decision;
@property (nonatomic, assign) NSInteger answer;
@end
@implementation LSReceiver
- (id)init {self=[super init];if(self){self.port=53317;self.listener=-1;self.clients=[NSMutableSet set];self.uploadSockets=[NSMutableSet set];self.decision=[[NSCondition alloc] init];}return self;}
- (NSDictionary *)deviceInfo {return @{@"alias":self.alias?:@"iPhone",@"version":@"2.0",@"deviceModel":@"iPhone",@"deviceType":@"mobile",@"fingerprint":LSLocalFingerprint(),@"port":@(self.port),@"protocol":@"https",@"download":@NO};}
- (void)emit {
    NSDictionary *state;
    @synchronized(self){if(!self.session)return;if(![@[@"offer",@"receiving"] containsObject:self.session[@"phase"]] && !self.session[@"ended"])self.session[@"ended"]=@([[NSDate date] timeIntervalSince1970]);NSMutableDictionary *copy=[self.session mutableCopy];NSMutableArray *files=[NSMutableArray array];for(NSString *fid in [self.session[@"files"] allKeys]){[files addObject:[self.session[@"files"][fid] copy]];}[files sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"fileName" ascending:YES]]];copy[@"items"]=files;[copy removeObjectForKey:@"files"];state=copy;}
    void (^handler)(NSDictionary *)=self.eventHandler;if(handler)dispatch_async(dispatch_get_main_queue(),^{handler(state);});
}
- (void)start:(void (^)(NSError *))completion {
    self.running=YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{@autoreleasepool{
        mbedtls_entropy_context e;mbedtls_entropy_init(&e);mbedtls_ctr_drbg_context rng;mbedtls_ctr_drbg_init(&rng);mbedtls_pk_context key;mbedtls_pk_init(&key);mbedtls_x509_crt cert;mbedtls_x509_crt_init(&cert);
        int ret=mbedtls_ctr_drbg_seed(&rng,mbedtls_entropy_func,&e,(unsigned char *)"LocalSend server",16);if(!ret)ret=LSSetupLocalIdentity(&rng,&key,&cert);mbedtls_pk_free(&key);mbedtls_x509_crt_free(&cert);mbedtls_ctr_drbg_free(&rng);mbedtls_entropy_free(&e);
        int fd=-1;if(!ret){fd=socket(AF_INET,SOCK_STREAM,0);int yes=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));struct sockaddr_in addr;memset(&addr,0,sizeof(addr));addr.sin_len=sizeof(addr);addr.sin_family=AF_INET;addr.sin_port=htons(self.port);addr.sin_addr.s_addr=htonl(INADDR_ANY);if(fd<0||bind(fd,(struct sockaddr *)&addr,sizeof(addr))||listen(fd,8)){ret=-1;if(fd>=0)close(fd);fd=-1;}else{socklen_t len=sizeof(addr);getsockname(fd,(struct sockaddr *)&addr,&len);self.port=ntohs(addr.sin_port);}}
        if(ret){self.running=NO;dispatch_async(dispatch_get_main_queue(),^{if(completion)completion([NSError errorWithDomain:@"LocalSendReceiver" code:ret userInfo:@{NSLocalizedDescriptionKey:LSL(@"Не удалось запустить HTTPS-приёмник")}]);});return;}
        self.listener=fd;self.ready=YES;dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(nil);});
        while(self.running){struct sockaddr_in from;socklen_t len=sizeof(from);int client=accept(fd,(struct sockaddr *)&from,&len);if(client<0){if(!self.running)break;continue;}NSString *ip=[NSString stringWithUTF8String:inet_ntoa(from.sin_addr)];
            @synchronized(self){if(self.clients.count>=8){close(client);continue;}[self.clients addObject:@(client)];}
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{@autoreleasepool{[self handleClient:client ip:ip];@synchronized(self){[self.clients removeObject:@(client)];}}});
        }
        close(fd);self.listener=-1;self.ready=NO;
    }});
}
- (void)stop {self.running=NO;self.ready=NO;[self cancel];if(self.listener>=0)shutdown(self.listener,SHUT_RDWR);@synchronized(self){for(NSNumber *fd in self.clients)shutdown(fd.intValue,SHUT_RDWR);}}
- (void)respond:(BOOL)accept {[self.decision lock];if(self.answer==0){self.answer=accept?1:-1;[self.decision broadcast];}[self.decision unlock];}
- (void)cancel {@synchronized(self){if(self.session && ![self.session[@"phase"] isEqual:@"complete"]){self.session[@"cancelled"]=@YES;self.session[@"phase"]=@"cancelled";for(NSNumber *socket in self.uploadSockets)shutdown(socket.intValue,SHUT_RDWR);}}[self respond:NO];[self emit];}
- (void)handleClient:(int)fd ip:(NSString *)ip {
    struct timeval timeout={30,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    mbedtls_net_context net;mbedtls_net_init(&net);net.fd=fd;mbedtls_entropy_context entropy;mbedtls_entropy_init(&entropy);mbedtls_ctr_drbg_context rng;mbedtls_ctr_drbg_init(&rng);mbedtls_pk_context key;mbedtls_pk_init(&key);mbedtls_x509_crt cert;mbedtls_x509_crt_init(&cert);mbedtls_ssl_context ssl;mbedtls_ssl_init(&ssl);mbedtls_ssl_config config;mbedtls_ssl_config_init(&config);
    int ret=mbedtls_ctr_drbg_seed(&rng,mbedtls_entropy_func,&entropy,(unsigned char *)"LS incoming",11);if(!ret)ret=LSSetupLocalIdentity(&rng,&key,&cert);if(!ret)ret=mbedtls_ssl_config_defaults(&config,MBEDTLS_SSL_IS_SERVER,MBEDTLS_SSL_TRANSPORT_STREAM,MBEDTLS_SSL_PRESET_DEFAULT);
    if(!ret){mbedtls_ssl_conf_min_tls_version(&config,MBEDTLS_SSL_VERSION_TLS1_2);mbedtls_ssl_conf_max_tls_version(&config,MBEDTLS_SSL_VERSION_TLS1_2);mbedtls_ssl_conf_rng(&config,mbedtls_ctr_drbg_random,&rng);mbedtls_ssl_conf_authmode(&config,MBEDTLS_SSL_VERIFY_OPTIONAL);mbedtls_ssl_conf_ca_chain(&config,&cert,NULL);mbedtls_ssl_conf_verify(&config,LSAllowClient,NULL);ret=mbedtls_ssl_conf_own_cert(&config,&cert,&key);}
    if(!ret)ret=mbedtls_ssl_setup(&ssl,&config);if(!ret){mbedtls_ssl_set_bio(&ssl,&net,mbedtls_net_send,mbedtls_net_recv,NULL);ret=mbedtls_ssl_handshake(&ssl);}if(!ret)[self route:&ssl ip:ip socket:fd];
    if(!ret)mbedtls_ssl_close_notify(&ssl);mbedtls_ssl_free(&ssl);mbedtls_ssl_config_free(&config);mbedtls_pk_free(&key);mbedtls_x509_crt_free(&cert);mbedtls_ctr_drbg_free(&rng);mbedtls_entropy_free(&entropy);mbedtls_net_free(&net);
}
- (void)route:(mbedtls_ssl_context *)ssl ip:(NSString *)ip socket:(int)fd {
    LSBody *reader=[[LSBody alloc] init];reader.ssl=ssl;reader.socket=fd;reader.buffer=[NSMutableData data];
    NSString *request=[reader line];NSArray *parts=[request componentsSeparatedByString:@" "];if(parts.count!=3){LSReply(ssl,400,nil);return;}NSString *method=parts[0];NSString *target=parts[1];NSMutableDictionary *headers=[NSMutableDictionary dictionary];NSUInteger headerSize=0;
    for(;;){NSString *line=[reader line];if(!line){return;}if(!line.length)break;headerSize+=line.length;if(headerSize>65536){LSReply(ssl,431,nil);return;}NSRange colon=[line rangeOfString:@":"];if(colon.location==NSNotFound){LSReply(ssl,400,nil);return;}NSString *name=[[line substringToIndex:colon.location] lowercaseString];if(headers[name]){LSReply(ssl,400,nil);return;}headers[name]=[[line substringFromIndex:colon.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];}
    reader.chunked=[headers[@"transfer-encoding"] isEqual:@"chunked"];
    if(headers[@"transfer-encoding"] && (!reader.chunked||headers[@"content-length"])){LSReply(ssl,400,nil);return;}
    if(headers[@"content-length"]){NSString *length=headers[@"content-length"];if(!length.length||[length rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound||length.length>18){LSReply(ssl,400,nil);return;}reader.remaining=[length longLongValue];}
    NSURL *url=[NSURL URLWithString:[@"https://localhost" stringByAppendingString:target]];NSString *path=url.path;NSMutableDictionary *query=[NSMutableDictionary dictionary];for(NSString *pair in [url.query componentsSeparatedByString:@"&"]){NSRange r=[pair rangeOfString:@"="];if(r.location!=NSNotFound)query[[[pair substringToIndex:r.location] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]=[[pair substringFromIndex:r.location+1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];}
    if([headers[@"expect"] caseInsensitiveCompare:@"100-continue"]==NSOrderedSame && headers[@"expect"]){const char *continueReply="HTTP/1.1 100 Continue\r\n\r\n";mbedtls_ssl_write(ssl,(unsigned char *)continueReply,strlen(continueReply));}
    if([path isEqual:@"/api/localsend/v2/info"] && [method isEqual:@"GET"]){LSReply(ssl,200,[self deviceInfo]);return;}
    if(![method isEqual:@"POST"]){LSReply(ssl,405,nil);return;}
    if([path isEqual:@"/api/localsend/v2/cancel"]){@synchronized(self){if(![query[@"sessionId"] isEqual:self.session[@"sessionId"]]||![ip isEqual:self.session[@"ip"]]){LSReply(ssl,403,nil);return;}}[self cancel];LSReply(ssl,200,nil);return;}
    if([path isEqual:@"/api/localsend/v2/upload"]){if(!reader.chunked&&!headers[@"content-length"]){LSReply(ssl,411,nil);return;}[self upload:reader query:query ip:ip];return;}
    if(![path isEqual:@"/api/localsend/v2/prepare-upload"] && ![path isEqual:@"/api/localsend/v2/register"]){LSReply(ssl,404,nil);return;}
    NSMutableData *body=[NSMutableData data];for(;;){NSData *chunk=[reader next];if(!chunk)break;[body appendData:chunk];if(body.length>1048576){LSReply(ssl,413,nil);return;}}if(reader.failed){LSReply(ssl,400,nil);return;}NSDictionary *json=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];if(![json isKindOfClass:[NSDictionary class]]){LSReply(ssl,400,nil);return;}
    if([path isEqual:@"/api/localsend/v2/register"]){if(self.peerHandler && [json[@"port"] respondsToSelector:@selector(integerValue)]){NSMutableDictionary *peer=[json mutableCopy];peer[@"ip"]=ip;peer[@"port"]=[json[@"port"] description];void (^callback)(NSDictionary *)=self.peerHandler;dispatch_async(dispatch_get_main_queue(),^{callback(peer);});}LSReply(ssl,200,[self deviceInfo]);return;}
    [self prepare:json ip:ip ssl:ssl];
}
- (void)prepare:(NSDictionary *)json ip:(NSString *)ip ssl:(mbedtls_ssl_context *)ssl {
    NSDictionary *incoming=json[@"files"];NSDictionary *info=json[@"info"];if(![incoming isKindOfClass:[NSDictionary class]]||!incoming.count||incoming.count>1000||![info isKindOfClass:[NSDictionary class]]){LSReply(ssl,400,nil);return;}
    NSMutableDictionary *files=[NSMutableDictionary dictionary],*tokens=[NSMutableDictionary dictionary];int64_t total=0;NSMutableSet *names=[NSMutableSet set];
    for(NSString *fid in incoming){NSDictionary *file=incoming[fid];if(![file isKindOfClass:[NSDictionary class]]||![file[@"fileName"] isKindOfClass:[NSString class]]||![file[@"size"] isKindOfClass:[NSNumber class]]){LSReply(ssl,400,nil);return;}NSString *name=[file[@"fileName"] lastPathComponent];int64_t size=[file[@"size"] longLongValue];if(!name.length||[name hasPrefix:@"."]||[name rangeOfString:@"\0"].location!=NSNotFound||size<0||size>INT64_MAX-total){LSReply(ssl,400,nil);return;}
        NSString *base=name;NSUInteger suffix=1;while([names containsObject:name]||[[NSFileManager defaultManager] fileExistsAtPath:[self.documentsPath stringByAppendingPathComponent:name]]){NSString *ext=base.pathExtension;name=[NSString stringWithFormat:@"%@ (%lu)%@%@",[base stringByDeletingPathExtension],(unsigned long)suffix++,ext.length?@".":@"",ext];}[names addObject:name];
        NSMutableDictionary *record=[file mutableCopy];record[@"id"]=fid;record[@"fileType"]=[file[@"fileType"] isKindOfClass:[NSString class]]?file[@"fileType"]:@"application/octet-stream";record[@"fileName"]=name;record[@"received"]=@0;record[@"status"]=@"Очередь";files[fid]=record;tokens[fid]=[[NSUUID UUID] UUIDString];total+=size;
    }
    unsigned long long free=[[[NSFileManager defaultManager] attributesOfFileSystemForPath:self.documentsPath error:nil][NSFileSystemFreeSize] unsignedLongLongValue];if((unsigned long long)total+1048576>free){LSReply(ssl,507,nil);return;}
    [self.decision lock];
    @synchronized(self){if(self.uploadSockets.count || (self.session && [@[@"offer",@"receiving"] containsObject:self.session[@"phase"]])){[self.decision unlock];LSReply(ssl,409,nil);return;}self.answer=0;self.session=[@{@"sessionId":[[NSUUID UUID] UUIDString],@"ip":ip,@"sender":([info[@"alias"] isKindOfClass:[NSString class]]?info[@"alias"]:@"LocalSend"),@"model":([info[@"deviceModel"] isKindOfClass:[NSString class]]?info[@"deviceModel"]:@"Устройство"),@"files":files,@"tokens":tokens,@"total":@(total),@"received":@0,@"completed":@0,@"phase":@"offer",@"cancelled":@NO,@"started":@([[NSDate date] timeIntervalSince1970])} mutableCopy];}
    [self emit];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:120];while(self.answer==0 && self.running){if(![self.decision waitUntilDate:deadline])break;}BOOL accepted=self.answer==1;[self.decision unlock];
    @synchronized(self){if([self.session[@"cancelled"] boolValue])accepted=NO;self.session[@"phase"]=accepted?@"receiving":@"rejected";self.session[@"started"]=@([[NSDate date] timeIntervalSince1970]);}
    [self emit];if(!accepted){LSReply(ssl,403,nil);return;}
    NSDictionary *reply;@synchronized(self){reply=@{@"sessionId":self.session[@"sessionId"],@"files":tokens};}
    if(!LSReply(ssl,200,reply))[self cancel];
}
- (void)upload:(LSBody *)reader query:(NSDictionary *)query ip:(NSString *)ip {
    NSMutableDictionary *file;NSMutableDictionary *session;
    @synchronized(self){session=self.session;file=session[@"files"][query[@"fileId"]?:@""];
        if(![query[@"sessionId"] isEqual:session[@"sessionId"]]||![ip isEqual:session[@"ip"]]||![query[@"token"] isEqual:session[@"tokens"][query[@"fileId"]?:@""]]||!file||[session[@"cancelled"] boolValue]){LSReply(reader.ssl,403,nil);return;}
        if(![file[@"status"] isEqual:@"Очередь"]){LSReply(reader.ssl,409,nil);return;}if(!reader.chunked && reader.remaining!=[file[@"size"] longLongValue]){LSReply(reader.ssl,400,nil);return;}file[@"status"]=@"Получение…";[self.uploadSockets addObject:@(reader.socket)];
    }
    NSString *temporary=[self.documentsPath stringByAppendingPathComponent:[@".incoming-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];FILE *out=fopen(temporary.fileSystemRepresentation,"wb");if(!out){@synchronized(self){[self.uploadSockets removeObject:@(reader.socket)];file[@"status"]=@"Ошибка записи";session[@"phase"]=@"failed";}[self emit];LSReply(reader.ssl,500,nil);return;}
    mbedtls_sha256_context sha;mbedtls_sha256_init(&sha);mbedtls_sha256_starts(&sha,0);BOOL ok=YES;int64_t received=0;NSTimeInterval last=0;[self emit];
    for(;;){@autoreleasepool{ @synchronized(self){if([session[@"cancelled"] boolValue]){ok=NO;break;}}NSData *chunk=[reader next];if(!chunk)break;if((int64_t)chunk.length>[file[@"size"] longLongValue]-received||fwrite(chunk.bytes,1,chunk.length,out)!=chunk.length){ok=NO;break;}mbedtls_sha256_update(&sha,chunk.bytes,chunk.length);received+=chunk.length;@synchronized(self){file[@"received"]=@(received);session[@"received"]=@([session[@"received"] longLongValue]+chunk.length);}NSTimeInterval now=[[NSDate date] timeIntervalSince1970];if(now-last>.12){[self emit];last=now;}}}
    if(fclose(out)!=0)ok=NO;unsigned char digest[32];mbedtls_sha256_finish(&sha,digest);mbedtls_sha256_free(&sha);NSMutableString *hash=[NSMutableString string];for(NSUInteger i=0;i<32;i++)[hash appendFormat:@"%02x",digest[i]];
    NSString *expected=[file[@"sha256"] isKindOfClass:[NSString class]]?file[@"sha256"]:nil;BOOL checksum=(!expected.length || [hash isEqual:[expected lowercaseString]]);
    @synchronized(self){if([session[@"cancelled"] boolValue])ok=NO;}ok=ok&&!reader.failed&&reader.finished&&received==[file[@"size"] longLongValue]&&checksum;
    NSString *destination=[self.documentsPath stringByAppendingPathComponent:file[@"fileName"]];if(ok)ok=[[NSFileManager defaultManager] moveItemAtPath:temporary toPath:destination error:nil];
    if(!ok)[[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
    @synchronized(self){[self.uploadSockets removeObject:@(reader.socket)];file[@"status"]=ok?@"Получено":@"Ошибка";if(ok){file[@"path"]=destination;session[@"completed"]=@([session[@"completed"] integerValue]+1);if([session[@"completed"] integerValue]==[session[@"files"] count])session[@"phase"]=@"complete";}else if(![session[@"cancelled"] boolValue]){session[@"phase"]=@"failed";session[@"cancelled"]=@YES;}}
    [self emit];LSReply(reader.ssl,ok?200:(checksum?500:422),nil);
}
@end
