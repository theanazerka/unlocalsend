#import <Foundation/Foundation.h>
@interface LSPhotoImporter : NSObject
@property (nonatomic, readonly, getter=isImporting) BOOL importing;
+ (BOOL)isImageFile:(NSDictionary *)file;
+ (BOOL)isVideoFile:(NSDictionary *)file;
+ (BOOL)isMediaFile:(NSDictionary *)file;
- (void)enqueueFiles:(NSArray *)files completion:(void (^)(NSString *path, NSError *error))completion;
@end
