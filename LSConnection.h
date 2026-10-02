#import <Foundation/Foundation.h>

// Use one instance for preparation and upload, so both requests use the same certificate.
@interface LSConnection : NSObject <NSURLConnectionDataDelegate>
@property (nonatomic, copy) NSString *expectedFingerprint;
- (NSData *)sendRequest:(NSURLRequest *)request response:(NSURLResponse **)response error:(NSError **)error;
@end
