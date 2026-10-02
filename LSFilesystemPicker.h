#import <UIKit/UIKit.h>
@interface LSFilesystemPicker : UITableViewController <UIAlertViewDelegate>
- (id)initWithDirectory:(NSString *)directory documents:(NSString *)documents dark:(BOOL)dark accent:(NSInteger)accent animations:(BOOL)animations selection:(void (^)(NSURL *url))selection;
@end
