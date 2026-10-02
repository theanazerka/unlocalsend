#import <Foundation/Foundation.h>
#import "mbedtls/ctr_drbg.h"
#import "mbedtls/pk.h"
#import "mbedtls/x509_crt.h"
int LSSetupLocalIdentity(mbedtls_ctr_drbg_context *rng, mbedtls_pk_context *key, mbedtls_x509_crt *cert);
NSString *LSLocalFingerprint(void);
