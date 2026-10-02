#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Each installation creates its own key in the keychain; the private key is never bundled.
@interface LSIdentity : NSObject
+ (NSURLCredential *)clientCredentialWithError:(NSError **)error;
@end

NSData *LSCreateCertificate(SecKeyRef privateKey, NSData *publicKey, NSError **error);
