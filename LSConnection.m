#import "LSConnection.h"
#import "LSIdentity.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

@interface LSConnection ()
@property (nonatomic, strong) NSMutableData *received;
@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSData *certificate;
@property (nonatomic, copy) NSString *host;
@property (nonatomic) BOOL finished;
@end

@implementation LSConnection
- (NSURLCredential *)clientCredentialWithError:(NSError **)error { return [LSIdentity clientCredentialWithError:error]; }
- (NSData *)sendRequest:(NSURLRequest *)request response:(NSURLResponse **)response error:(NSError **)error {
    self.received = [NSMutableData data]; self.response = nil; self.error = nil; self.finished = NO;
    self.host = [[request.URL host] lowercaseString];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    if (!connection) {
        self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
        self.finished = YES;
    } else {
        [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [connection start];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:request.timeoutInterval + 5];
        while (!self.finished && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        if (!self.finished) {
            [connection cancel];
            self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        }
    }
    if (response) *response = self.response;
    if (error) *error = self.error;
    return self.error ? nil : self.received;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.response = response; [self.received setLength:0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data { [self.received appendData:data]; }
- (void)connectionDidFinishLoading:(NSURLConnection *)connection { self.finished = YES; }
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error { if (!self.error) self.error = error; self.finished = YES; }
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
    if (response) {
        self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorHTTPTooManyRedirects userInfo:nil];
        self.finished = YES; [connection cancel]; return nil;
    }
    return request;
}
- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)space {
    return [space.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] || [space.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate];
}
- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if ([space.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate]) {
        NSError *identityError = nil; NSURLCredential *credential = [self clientCredentialWithError:&identityError];
        if (credential && challenge.previousFailureCount == 0) {
            [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
        } else {
            self.error = identityError ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorClientCertificateRejected userInfo:nil];
            self.finished = YES; [challenge.sender cancelAuthenticationChallenge:challenge];
        }
        return;
    }
    if (![space.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge]; return;
    }
    SecTrustRef trust = space.serverTrust;
    SecCertificateRef cert = trust ? SecTrustGetCertificateAtIndex(trust, 0) : NULL;
    NSData *der = cert ? CFBridgingRelease(SecCertificateCopyData(cert)) : nil;
    BOOL accepted = der && [[space.host lowercaseString] isEqual:self.host] && challenge.previousFailureCount == 0;
    if (self.certificate && ![self.certificate isEqualToData:der]) accepted = NO;
    if ([self.expectedFingerprint length]) {
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(der.bytes, (CC_LONG)der.length, digest);
        NSMutableString *fingerprint = [NSMutableString string];
        for (NSUInteger i = 0; i < sizeof(digest); i++) [fingerprint appendFormat:@"%02x", digest[i]];
        NSString *expected = [[self.expectedFingerprint stringByReplacingOccurrencesOfString:@":" withString:@""] lowercaseString];
        if (![fingerprint isEqualToString:expected]) accepted = NO;
    }
    if (accepted) {
        self.certificate = der;
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:trust] forAuthenticationChallenge:challenge];
    } else {
        self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted userInfo:@{NSLocalizedDescriptionKey: @"Сертификат получателя не совпадает с объявленным LocalSend"}];
        self.finished = YES; [challenge.sender cancelAuthenticationChallenge:challenge];
    }
}
@end
