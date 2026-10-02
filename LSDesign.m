#import "LSLocalization.h"
#import "LSDesign.h"
UIColor *LSBackground(BOOL dark) { return dark ? [UIColor colorWithRed:.075 green:.12 blue:.115 alpha:1] : [UIColor colorWithRed:.953 green:.980 blue:.973 alpha:1]; }
UIColor *LSTextColor(BOOL dark) { return dark ? [UIColor colorWithWhite:.94 alpha:1] : [UIColor colorWithRed:.085 green:.125 blue:.12 alpha:1]; }
UIColor *LSAccent(NSInteger color) { if (color == 1) return [UIColor colorWithRed:.24 green:.39 blue:.80 alpha:1]; if (color == 2) return [UIColor colorWithRed:.57 green:.28 blue:.72 alpha:1]; return [UIColor colorWithRed:0 green:.42 blue:.38 alpha:1]; }
@implementation LSCardView {
    CALayer *_cardBackground;
}
- (id)initWithColor:(UIColor *)color shadowOpacity:(CGFloat)opacity {
    self=[super initWithFrame:CGRectZero];
    if(self){
        // Bake the rounded surface and shadow once. Scrolling only composites
        // a nine-slice image, without per-frame shadow or mask rendering.
        static NSCache *backgrounds;static dispatch_once_t once;
        dispatch_once(&once,^{backgrounds=[[NSCache alloc] init];backgrounds.countLimit=8;});
        NSString *key=[NSString stringWithFormat:@"%@/%.3f/%.1f",color,opacity,[UIScreen mainScreen].scale];
        UIImage *image=[backgrounds objectForKey:key];
        if(!image){
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(48,48),NO,0);
            CGContextRef context=UIGraphicsGetCurrentContext();
            CGContextSetShadowWithColor(context,CGSizeMake(0,2),2,[UIColor colorWithWhite:0 alpha:opacity].CGColor);
            [color setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(4,4,40,40) cornerRadius:13] fill];
            image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
            [backgrounds setObject:image forKey:key];
        }
        _cardBackground=[CALayer layer];_cardBackground.contents=(id)image.CGImage;
        _cardBackground.contentsScale=image.scale;
        _cardBackground.contentsCenter=CGRectMake(18.0/48,18.0/48,12.0/48,12.0/48);
        _cardBackground.actions=@{@"bounds":[NSNull null],@"position":[NSNull null]};
        [self.layer addSublayer:_cardBackground];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews];_cardBackground.frame=CGRectInset(self.bounds,-4,-4); }
@end
@implementation LSLayoutController {
    CGRect _laidOutBounds;
    BOOL _hasLaidOutBounds;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(_hasLaidOutBounds && CGRectEqualToRect(_laidOutBounds,self.view.bounds))return;
    _laidOutBounds=self.view.bounds;_hasLaidOutBounds=YES;
    if ([self.layoutDelegate respondsToSelector:@selector(layoutInterface)]) [self.layoutDelegate performSelector:@selector(layoutInterface)];
}
- (BOOL)shouldAutorotate { return NO; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end
static void LSLine(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) { UIBezierPath *p=[UIBezierPath bezierPath]; [p moveToPoint:CGPointMake(x1,y1)]; [p addLineToPoint:CGPointMake(x2,y2)]; p.lineWidth=1.8; [p stroke]; }
static void LSLogo(void);
#include "LSSuppliedIcons.inc"
UIImage *LSIcon(NSString *name, UIColor *color, CGFloat size) {
    static NSCache *icons;static dispatch_once_t once;
    dispatch_once(&once,^{icons=[[NSCache alloc] init];icons.countLimit=64;});
    NSString *key=[NSString stringWithFormat:@"%@/%@/%.2f/%.1f",name,color,size,[UIScreen mainScreen].scale];
    UIImage *cached=[icons objectForKey:key];if(cached)return cached;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size,size), NO, 0);
    CGContextRef c=UIGraphicsGetCurrentContext(); CGContextScaleCTM(c,size/24,size/24);
    [color setFill]; [color setStroke]; CGContextSetLineCap(c,kCGLineCapRound); CGContextSetLineJoin(c,kCGLineJoinRound);
    if ([name isEqual:@"logo"]) LSLogo();
    else if (LSSuppliedIcon(name,c)) {}
    else if ([name isEqual:@"send"]) { UIBezierPath *p=[UIBezierPath bezierPath]; [p moveToPoint:CGPointMake(3,3)]; [p addLineToPoint:CGPointMake(22,12)]; [p addLineToPoint:CGPointMake(3,21)]; [p addLineToPoint:CGPointMake(3,14)]; [p addLineToPoint:CGPointMake(15,12)]; [p addLineToPoint:CGPointMake(3,10)]; [p closePath]; [p fill]; }
    else if ([name isEqual:@"media"]) { [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3,3,18,18) cornerRadius:2] fill]; CGContextSaveGState(c); CGContextSetBlendMode(c,kCGBlendModeClear); UIBezierPath *p=[UIBezierPath bezierPath]; [p moveToPoint:CGPointMake(5,18)]; [p addLineToPoint:CGPointMake(10,11)]; [p addLineToPoint:CGPointMake(13,15)]; [p addLineToPoint:CGPointMake(16,10)]; [p addLineToPoint:CGPointMake(20,18)]; [p closePath]; [p fill]; CGContextRestoreGState(c); }
    else if ([name isEqual:@"text"]) { for(int i=0;i<4;i++) LSLine(4,6+i*4,i==3?12:20,6+i*4); }
    else if ([name isEqual:@"folder"]) { UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,6,20,15) cornerRadius:2]; [p fill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,3,9,8) cornerRadius:2] fill]; }
    else if ([name isEqual:@"file"]) { UIBezierPath *p=[UIBezierPath bezierPath]; [p moveToPoint:CGPointMake(5,2)]; [p addLineToPoint:CGPointMake(14,2)]; [p addLineToPoint:CGPointMake(20,8)]; [p addLineToPoint:CGPointMake(20,22)]; [p addLineToPoint:CGPointMake(5,22)]; [p closePath]; p.lineWidth=1.7; [p stroke]; LSLine(14,2,14,8); LSLine(14,8,20,8); LSLine(8,13,17,13); LSLine(8,17,17,17); }
    else if ([name isEqual:@"paste"]) { UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5,4,14,18) cornerRadius:1]; p.lineWidth=1.8; [p stroke]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9,1,6,5) cornerRadius:1] fill]; }
    else if ([name isEqual:@"refresh"]) { UIBezierPath *p=[UIBezierPath bezierPathWithArcCenter:CGPointMake(12,12) radius:8 startAngle:-2.5 endAngle:2.5 clockwise:YES]; p.lineWidth=2; [p stroke]; UIBezierPath *a=[UIBezierPath bezierPath]; [a moveToPoint:CGPointMake(2,3)]; [a addLineToPoint:CGPointMake(9,5)]; [a addLineToPoint:CGPointMake(3,10)]; [a closePath]; [a fill]; }
    else if ([name isEqual:@"device"]) { UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6,1,12,22) cornerRadius:2]; p.lineWidth=1.6; [p stroke]; LSLine(9,19,15,19); }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); [icons setObject:image forKey:key]; return image;
}

static void LSLogo(void) {
 CGContextRef c=UIGraphicsGetCurrentContext();
CGContextMoveToPoint(c, 5.5380000, 12.0150000);
CGContextAddCurveToPoint(c, 5.5402085, 8.4483448, 8.4333448, 5.5587902, 12.0000000, 5.5610000);
CGContextAddCurveToPoint(c, 15.5666552, 5.5587902, 18.4597915, 8.4483448, 18.4620000, 12.0150000);
CGContextAddCurveToPoint(c, 18.4160120, 15.5503663, 15.5356645, 18.3914890, 12.0000000, 18.3890000);
CGContextAddCurveToPoint(c, 8.4647249, 18.3909413, 5.5849832, 15.5499766, 5.5390000, 12.0150000);
CGContextAddLineToPoint(c, 5.5380000, 12.0150000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 22.5300000, 6.2620000);
CGContextAddCurveToPoint(c, 21.7226321, 6.7884371, 20.6461958, 6.6055475, 20.0580000, 5.8420000);
CGContextAddCurveToPoint(c, 19.5164677, 5.1380922, 18.8854847, 4.5077816, 18.1810000, 3.9670000);
CGContextAddCurveToPoint(c, 17.4170884, 3.3804328, 17.2336396, 2.3045771, 17.7600000, 1.4980000);
CGContextAddCurveToPoint(c, 19.7709458, 2.5997327, 21.4257371, 4.2524425, 22.5300000, 6.2620000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 3.9430000, 5.8420000);
CGContextAddCurveToPoint(c, 3.3548042, 6.6055475, 2.2783679, 6.7884371, 1.4710000, 6.2620000);
CGContextAddCurveToPoint(c, 2.5752629, 4.2524425, 4.2300542, 2.5997327, 6.2410000, 1.4980000);
CGContextAddCurveToPoint(c, 6.7675797, 2.3043289, 6.5845744, 3.3801384, 5.8210000, 3.9670000);
CGContextAddCurveToPoint(c, 5.1161629, 4.5077147, 4.4848409, 5.1380283, 3.9430000, 5.8420000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 24.0000000, 12.0150000);
CGContextAddCurveToPoint(c, 24.0010000, 13.1550000, 23.8400000, 14.2900000, 23.5200000, 15.3850000);
CGContextAddCurveToPoint(c, 22.5764372, 15.1881504, 21.9436656, 14.2978250, 22.0680000, 13.3420000);
CGContextAddCurveToPoint(c, 22.1830000, 12.4620000, 22.1830000, 11.5690000, 22.0680000, 10.6880000);
CGContextAddCurveToPoint(c, 21.9435985, 9.7324898, 22.5758407, 8.8422963, 23.5190000, 8.6450000);
CGContextAddCurveToPoint(c, 23.8390000, 9.7400000, 24.0010000, 10.8750000, 24.0000000, 12.0150000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 0.0000000, 12.0150000);
CGContextAddCurveToPoint(c, 0.0000000, 10.8750000, 0.1620000, 9.7400000, 0.4820000, 8.6450000);
CGContextAddCurveToPoint(c, 1.4247559, 8.8427427, 2.0564689, 9.7328045, 1.9320000, 10.6880000);
CGContextAddCurveToPoint(c, 1.8170000, 11.5680000, 1.8170000, 12.4610000, 1.9320000, 13.3420000);
CGContextAddCurveToPoint(c, 2.0564689, 14.2971955, 1.4247559, 15.1872573, 0.4820000, 15.3850000);
CGContextAddCurveToPoint(c, 0.1615179, 14.2900428, -0.0007905, 13.1548941, 0.0000000, 12.0140000);
CGContextAddLineToPoint(c, 0.0000000, 12.0150000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 17.7600000, 22.5330000);
CGContextAddCurveToPoint(c, 17.2327897, 21.7264658, 17.4158411, 20.6499491, 18.1800000, 20.0630000);
CGContextAddCurveToPoint(c, 18.8848446, 19.5222939, 19.5161677, 18.8919793, 20.0580000, 18.1880000);
CGContextAddCurveToPoint(c, 20.6461958, 17.4244525, 21.7226321, 17.2415629, 22.5300000, 17.7680000);
CGContextAddCurveToPoint(c, 21.4258889, 19.7779265, 19.7710834, 21.4309974, 17.7600000, 22.5330000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 6.2410000, 22.5330000);
CGContextAddCurveToPoint(c, 4.2300542, 21.4312673, 2.5752629, 19.7785575, 1.4710000, 17.7690000);
CGContextAddCurveToPoint(c, 2.2783679, 17.2425629, 3.3548042, 17.4254525, 3.9430000, 18.1890000);
CGContextAddCurveToPoint(c, 4.4845990, 18.8925554, 5.1155792, 19.5225270, 5.8200000, 20.0630000);
CGContextAddCurveToPoint(c, 6.5850000, 20.6500000, 6.7680000, 21.7260000, 6.2410000, 22.5330000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 12.0010000, 24.0000000);
CGContextAddCurveToPoint(c, 10.8588977, 24.0013154, 9.7224486, 23.8396871, 8.6260000, 23.5200000);
CGContextAddCurveToPoint(c, 8.8246755, 22.5765172, 9.7159829, 21.9448478, 10.6720000, 22.0700000);
CGContextAddCurveToPoint(c, 11.5540000, 22.1850000, 12.4470000, 22.1850000, 13.3290000, 22.0700000);
CGContextAddCurveToPoint(c, 14.2847028, 21.9447799, 15.1758787, 22.5759206, 15.3750000, 23.5190000);
CGContextAddCurveToPoint(c, 14.2790000, 23.8390000, 13.1420000, 24.0010000, 12.0000000, 24.0000000);
CGContextAddLineToPoint(c, 12.0010000, 24.0000000);
CGContextClosePath(c);
CGContextMoveToPoint(c, 13.5070000, 1.9430000);
CGContextAddCurveToPoint(c, 12.5620000, 1.8070000, 11.6190000, 1.8430000, 10.6730000, 1.9300000);
CGContextAddCurveToPoint(c, 9.7168754, 2.0547092, 8.8255641, 1.4233456, 8.6260000, 0.4800000);
CGContextAddCurveToPoint(c, 9.7218198, 0.1605679, 10.8575725, -0.0010571, 11.9990000, -0.0000000);
CGContextAddLineToPoint(c, 12.0010000, 0.0000000);
CGContextAddCurveToPoint(c, 13.1430000, -0.0010000, 14.2780000, 0.1600000, 15.3740000, 0.4800000);
CGContextAddCurveToPoint(c, 15.1891150, 1.3560930, 14.4018872, 1.9729727, 13.5070000, 1.9430000);
CGContextClosePath(c);
 CGContextFillPath(c);
}

@implementation LSFlatSwitch {
    UIView *_track;
    UIView *_thumb;
}
- (id)init {
    self=[super initWithFrame:CGRectMake(0,0,52,31)];
    if(self){self.backgroundColor=[UIColor clearColor];_animationsEnabled=YES;_onTintColor=LSAccent(0);self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
        _track=[[UIView alloc] init];_track.userInteractionEnabled=NO;_track.layer.borderWidth=1.7;[self addSubview:_track];
        _thumb=[[UIView alloc] init];_thumb.userInteractionEnabled=NO;[self addSubview:_thumb];
        [self updateAppearance];[self addTarget:self action:@selector(flip) forControlEvents:UIControlEventTouchUpInside];}
    return self;
}
- (void)updateAppearance {
    _track.frame=CGRectInset(self.bounds,1,1);_track.layer.cornerRadius=_track.bounds.size.height/2;
    _track.backgroundColor=self.on?self.onTintColor:[UIColor clearColor];_track.layer.borderColor=(self.on?self.onTintColor:[UIColor colorWithWhite:.5 alpha:1]).CGColor;
    CGFloat diameter=self.bounds.size.height-8;
    _thumb.frame=CGRectMake(self.on?self.bounds.size.width-diameter-4:4,4,diameter,diameter);_thumb.layer.cornerRadius=diameter/2;
    _thumb.backgroundColor=self.on?[UIColor whiteColor]:[UIColor colorWithWhite:.5 alpha:1];
}
- (void)layoutSubviews {[super layoutSubviews];[self updateAppearance];}
- (void)setOn:(BOOL)on {[self setOn:on animated:NO];}
- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on=on;self.accessibilityValue=on?LSL(@"Включено"):LSL(@"Выключено");
    if(animated && self.animationsEnabled){[UIView animateWithDuration:.24 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseInOut animations:^{[self updateAppearance];} completion:nil];}
    else [self updateAppearance];
}
- (void)setOnTintColor:(UIColor *)color {_onTintColor=color;[self updateAppearance];}
- (void)flip {[self setOn:!self.on animated:YES];[self sendActionsForControlEvents:UIControlEventValueChanged];}
- (BOOL)accessibilityActivate {[self flip];return YES;}
@end
