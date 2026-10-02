#import "LSIdentity.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>

static NSData *DER(unsigned char tag, NSData *content) {
    NSMutableData *out = [NSMutableData dataWithBytes:&tag length:1];
    NSUInteger length = content.length;
    if (length < 128) { unsigned char byte = (unsigned char)length; [out appendBytes:&byte length:1]; }
    else {
        unsigned char bytes[sizeof(NSUInteger)], count = 0;
        for (NSUInteger n = length; n; n >>= 8) bytes[sizeof(bytes) - ++count] = n & 255;
        unsigned char prefix = 0x80 | count; [out appendBytes:&prefix length:1];
        [out appendBytes:bytes + sizeof(bytes) - count length:count];
    }
    [out appendData:content]; return out;
}
static NSData *Join(NSArray *parts) { NSMutableData *data = [NSMutableData data]; for (NSData *part in parts) [data appendData:part]; return data; }
static NSData *Bytes(const unsigned char *bytes, NSUInteger length) { return [NSData dataWithBytes:bytes length:length]; }
static NSData *OID(const unsigned char *bytes, NSUInteger length) { return DER(0x06, Bytes(bytes, length)); }
static NSError *IdentityError(NSString *message, OSStatus status) { return [NSError errorWithDomain:@"LocalSendIdentity" code:status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"%@ (%ld)",message,(long)status]}]; }

NSData *LSCreateCertificate(SecKeyRef privateKey, NSData *publicKey, NSError **error) {
    const unsigned char rsa[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01};
    const unsigned char shaRSA[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b};
    const unsigned char cn[] = {0x55,0x04,0x03};
    NSData *null = DER(0x05,[NSData data]);
    NSData *algorithm = DER(0x30,Join(@[OID(shaRSA,sizeof(shaRSA)),null]));
    NSData *subject = DER(0x30,DER(0x31,DER(0x30,Join(@[OID(cn,sizeof(cn)),DER(0x0c,[@"LocalSend User" dataUsingEncoding:NSUTF8StringEncoding])]))));
    unsigned char serial[16]; OSStatus status = SecRandomCopyBytes(kSecRandomDefault,sizeof(serial),serial);
    if (status) { if (error) *error = IdentityError(@"Не удалось создать номер сертификата",status); return nil; }
    serial[0] = (serial[0] & 0x7f) | 1;
    NSData *validity = DER(0x30,Join(@[DER(0x17,[@"750101000000Z" dataUsingEncoding:NSASCIIStringEncoding]),DER(0x18,[@"40960101000000Z" dataUsingEncoding:NSASCIIStringEncoding])]));
    unsigned char zero = 0, two = 2, yes = 255;
    NSData *publicInfo = DER(0x30,Join(@[DER(0x30,Join(@[OID(rsa,sizeof(rsa)),null])),DER(0x03,Join(@[Bytes(&zero,1),publicKey]))]));
    const unsigned char basic[] = {0x55,0x1d,0x13}, usage[] = {0x55,0x1d,0x0f}, extended[] = {0x55,0x1d,0x25};
    const unsigned char clientAuth[] = {0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x02}, digitalSignature[] = {7,0x80};
    NSData *extensions = DER(0xa3,DER(0x30,Join(@[
        DER(0x30,Join(@[OID(basic,sizeof(basic)),DER(0x01,Bytes(&yes,1)),DER(0x04,DER(0x30,[NSData data]))])),
        DER(0x30,Join(@[OID(usage,sizeof(usage)),DER(0x01,Bytes(&yes,1)),DER(0x04,DER(0x03,Bytes(digitalSignature,sizeof(digitalSignature))))])),
        DER(0x30,Join(@[OID(extended,sizeof(extended)),DER(0x04,DER(0x30,OID(clientAuth,sizeof(clientAuth))))]))
    ])));
    NSData *tbs = DER(0x30,Join(@[DER(0xa0,DER(0x02,Bytes(&two,1))),DER(0x02,Bytes(serial,sizeof(serial))),algorithm,subject,validity,subject,publicInfo,extensions]));
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(tbs.bytes,(CC_LONG)tbs.length,digest);
    NSMutableData *signature = [NSMutableData dataWithLength:SecKeyGetBlockSize(privateKey)]; size_t signatureLength = signature.length;
#if TARGET_OS_IPHONE
    status = SecKeyRawSign(privateKey,kSecPaddingPKCS1SHA256,digest,sizeof(digest),signature.mutableBytes,&signatureLength);
#else
    CFErrorRef signError = NULL;
    NSData *signedData = CFBridgingRelease(SecKeyCreateSignature(privateKey,kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256,(__bridge CFDataRef)Bytes(digest,sizeof(digest)),&signError));
    status = signedData ? errSecSuccess : errSecParam; if (signError) CFRelease(signError);
    if (signedData) { signature = [signedData mutableCopy]; signatureLength = signature.length; }
#endif
    if (status) { if (error) *error = IdentityError(@"Не удалось подписать сертификат",status); return nil; }
    [signature setLength:signatureLength];
    return DER(0x30,Join(@[tbs,algorithm,DER(0x03,Join(@[Bytes(&zero,1),signature]))]));
}

@implementation LSIdentity
+ (NSURLCredential *)clientCredentialWithError:(NSError **)error {
    @synchronized(self) {
        static NSURLCredential *cached = nil; if (cached) return cached;
        NSData *privateTag = [@"com.unlocalsend.tls.private.v1" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *publicTag = [@"com.unlocalsend.tls.public.v1" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *privateQuery = @{(__bridge id)kSecClass:(__bridge id)kSecClassKey,(__bridge id)kSecAttrApplicationTag:privateTag,(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecReturnRef:@YES};
        CFTypeRef keyRef = NULL; OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)privateQuery,&keyRef);
        SecKeyRef privateKey = (SecKeyRef)keyRef;
        BOOL generated = NO;
        if (status == errSecItemNotFound) {
            NSDictionary *attributes = @{(__bridge id)kSecAttrIsPermanent:@YES,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
            NSMutableDictionary *priv = [attributes mutableCopy]; priv[(__bridge id)kSecAttrApplicationTag] = privateTag;
            NSMutableDictionary *pub = [attributes mutableCopy]; pub[(__bridge id)kSecAttrApplicationTag] = publicTag;
            NSDictionary *params = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecAttrKeySizeInBits:@2048,(__bridge id)kSecPrivateKeyAttrs:priv,(__bridge id)kSecPublicKeyAttrs:pub};
            SecKeyRef publicKey = NULL; status = SecKeyGeneratePair((__bridge CFDictionaryRef)params,&publicKey,&privateKey); if (publicKey) CFRelease(publicKey);
            generated = (status == errSecSuccess);
        }
        if (status || !privateKey) { if (error) *error = IdentityError(@"Не удалось открыть TLS ключ",status); return nil; }
        NSData *der = generated ? nil : [[NSUserDefaults standardUserDefaults] dataForKey:@"LocalSendClientCertificate"];
        if (!der) {
            NSDictionary *pubQuery = @{(__bridge id)kSecClass:(__bridge id)kSecClassKey,(__bridge id)kSecAttrApplicationTag:publicTag,(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeRSA,(__bridge id)kSecReturnData:@YES};
            CFTypeRef pubData = NULL; status = SecItemCopyMatching((__bridge CFDictionaryRef)pubQuery,&pubData);
            if (status) { CFRelease(privateKey); if (error) *error = IdentityError(@"Не удалось прочитать публичный ключ",status); return nil; }
            der = LSCreateCertificate(privateKey,CFBridgingRelease(pubData),error);
        }
        CFRelease(privateKey); if (!der) return nil;
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL,(__bridge CFDataRef)der);
        if (!certificate) { if (error) *error = IdentityError(@"Неверный клиентский сертификат",errSecDecode); return nil; }
        status = SecItemAdd((__bridge CFDictionaryRef)@{(__bridge id)kSecClass:(__bridge id)kSecClassCertificate,(__bridge id)kSecValueRef:(__bridge id)certificate,(__bridge id)kSecAttrLabel:@"LocalSend 6 TLS"},NULL);
        if (status != errSecSuccess && status != errSecDuplicateItem) { CFRelease(certificate); if (error) *error = IdentityError(@"Не удалось сохранить клиентский сертификат",status); return nil; }
        [[NSUserDefaults standardUserDefaults] setObject:der forKey:@"LocalSendClientCertificate"];
        CFTypeRef identitiesRef = NULL;
        status = SecItemCopyMatching((__bridge CFDictionaryRef)@{(__bridge id)kSecClass:(__bridge id)kSecClassIdentity,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,(__bridge id)kSecReturnRef:@YES},&identitiesRef);
        NSArray *identities = CFBridgingRelease(identitiesRef);
        for (id item in identities) {
            SecIdentityRef identity = (__bridge SecIdentityRef)item; SecCertificateRef candidate = NULL;
            if (SecIdentityCopyCertificate(identity,&candidate) == errSecSuccess) {
                NSData *candidateDER = CFBridgingRelease(SecCertificateCopyData(candidate)); CFRelease(candidate);
                if ([candidateDER isEqualToData:der]) { cached = [NSURLCredential credentialWithIdentity:identity certificates:@[(__bridge id)certificate] persistence:NSURLCredentialPersistenceForSession]; break; }
            }
        }
        CFRelease(certificate);
        if (!cached && error) *error = IdentityError(@"Не удалось связать сертификат с TLS ключом",status ?: errSecItemNotFound);
        return cached;
    }
}
@end
