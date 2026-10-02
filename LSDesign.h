#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
UIColor *LSBackground(BOOL dark);
UIColor *LSTextColor(BOOL dark);
UIColor *LSAccent(NSInteger color);
UIImage *LSIcon(NSString *name, UIColor *color, CGFloat size);
@interface LSCardView : UIView
- (id)initWithColor:(UIColor *)color shadowOpacity:(CGFloat)opacity;
@end
@interface LSLayoutController : UIViewController
@property (nonatomic, weak) id layoutDelegate;
@end
@interface LSFlatSwitch : UIControl
@property (nonatomic, assign) BOOL on;
@property (nonatomic, assign) BOOL animationsEnabled;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@property (nonatomic, strong) UIColor *onTintColor;
@end
