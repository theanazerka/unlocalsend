#import <Foundation/Foundation.h>

NSData *LSHTTPSRequest(NSURLRequest *request, NSString *fingerprint,
                       NSURLResponse **response, NSError **error);

NSData *LSHTTPSRequestWithProgress(NSURLRequest *request, NSString *fingerprint, NSURLResponse **response, NSError **error, void (^progress)(NSString *, double));
