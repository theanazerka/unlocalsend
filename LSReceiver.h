#import <Foundation/Foundation.h>
@interface LSReceiver : NSObject
@property (nonatomic, copy) NSString *alias;
@property (nonatomic, copy) NSString *documentsPath;
@property (nonatomic, assign) NSUInteger port;
@property (atomic, readonly) BOOL ready;
@property (nonatomic, copy) void (^eventHandler)(NSDictionary *state);
@property (nonatomic, copy) void (^peerHandler)(NSDictionary *peer);
- (NSDictionary *)deviceInfo;
- (void)start:(void (^)(NSError *error))completion;
- (void)stop;
- (void)respond:(BOOL)accept;
- (void)cancel;
@end
