#import "AppDelegate.h"
#import "LSTransport.h"
#import "LSConnection.h"
#import "LSDesign.h"
#import "LSLocalization.h"
#import "LSFilesystemPicker.h"

#import "LSReceiver.h"
#import "LSTLSIdentity.h"
#import "LSPhotoImporter.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <netdb.h>
#import <ifaddrs.h>
#import <net/if.h>

@interface AppDelegate ()
@property (nonatomic, strong) NSMutableArray *peers;
@property (nonatomic, strong) NSArray *files;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) int discoverySocket;
@property (nonatomic, assign) BOOL discovering;
@property (nonatomic, strong) UIScrollView *content;
@property (nonatomic, strong) UIView *tabBar;
@property (nonatomic, strong) UIView *tabIndicator;
@property (nonatomic, strong) NSMutableArray *tabButtons;
@property (nonatomic, strong) UIView *selectionCard;
@property (nonatomic, strong) UILabel *selectionLabel;
@property (nonatomic, copy) NSString *selectedFile;
@property (nonatomic, assign) NSInteger activeTab;
@property (nonatomic, assign) BOOL browsingFiles;
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, assign) NSInteger accentIndex;
@property (nonatomic, assign) BOOL animations;
@property (nonatomic, strong) NSMutableArray *history;
@property (nonatomic, strong) NSMutableArray *selectionButtons;
@property (nonatomic, strong) UILabel *devicesTitle;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *receivePanel;
@property (nonatomic, strong) UIView *settingsPanel;
@property (nonatomic, copy) NSString *deviceAlias;
@property (nonatomic, assign) BOOL sending;
@property (nonatomic, strong) LSReceiver *receiver;
@property (nonatomic, strong) NSDictionary *receiveState;
@property (nonatomic, strong) UIView *receiveOverlay;
@property (nonatomic, assign) BOOL receiveDetails;
@property (nonatomic, strong) NSTimer *receiveTimer;
@property (nonatomic, copy) NSString *localFingerprint;
@property (nonatomic, strong) UIDocumentInteractionController *documentViewer;
@property (nonatomic, assign) BOOL manualHostVisible;
@property (nonatomic, strong) LSPhotoImporter *photoImporter;
@property (nonatomic, strong) NSMutableDictionary *photoResults;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.photoImporter=[[LSPhotoImporter alloc] init]; self.photoResults=[NSMutableDictionary dictionary];
    self.peers = [NSMutableArray array]; self.discoverySocket = -1;
    self.darkTheme = [defaults boolForKey:@"darkTheme"];
    self.accentIndex = [defaults integerForKey:@"accentIndex"];
    self.animations = [defaults objectForKey:@"animations"] ? [defaults boolForKey:@"animations"] : YES;
    self.deviceAlias = [defaults stringForKey:@"deviceAlias"] ?: [[UIDevice currentDevice] name];
    self.history = [[defaults arrayForKey:@"transferHistory"] mutableCopy] ?: [NSMutableArray array];
    self.activeTab = 1;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    LSLayoutController *vc = [[LSLayoutController alloc] init]; vc.layoutDelegate = self;
    self.window.rootViewController = vc; [self buildInterface];
    [self.window makeKeyAndVisible]; [self refreshFiles];
    self.receiver=[[LSReceiver alloc] init]; self.receiver.alias=self.deviceAlias; self.receiver.documentsPath=[self documentsPath];
    __weak AppDelegate *weakSelf=self;
    self.receiver.eventHandler=^(NSDictionary *state){[weakSelf receiverChanged:state];};
    self.receiver.peerHandler=^(NSDictionary *peer){[weakSelf addPeer:peer];};
    [self.receiver start:^(NSError *error){if(error){[weakSelf showMessage:error.localizedDescription];return;}weakSelf.localFingerprint=LSLocalFingerprint();[weakSelf startDiscovery];[weakSelf updateLogoAnimation];}];
    return YES;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *label = [[UILabel alloc] init]; label.text = text; label.font = [UIFont systemFontOfSize:size];
    label.textColor = LSTextColor(self.darkTheme); label.backgroundColor = [UIColor clearColor]; label.numberOfLines = 0;
    return label;
}
- (UIView *)card {
    UIColor *color=self.darkTheme ? [UIColor colorWithRed:.11 green:.17 blue:.16 alpha:1] : [UIColor colorWithRed:.935 green:.961 blue:.952 alpha:1];
    return [[LSCardView alloc] initWithColor:color shadowOpacity:self.darkTheme?.08:.12];
}
- (UIButton *)button:(NSString *)title icon:(NSString *)icon action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal]; [button setTitleColor:LSAccent(self.accentIndex) forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14];
    if (icon) [button setImage:LSIcon(icon, LSAccent(self.accentIndex), 22) forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (void)buildInterface {
    UIView *root = self.window.rootViewController.view;
    for (UIView *v in [root.subviews copy]) [v removeFromSuperview];
    root.backgroundColor = LSBackground(self.darkTheme);
    self.content = [[UIScrollView alloc] init]; self.content.alwaysBounceVertical = YES; [root addSubview:self.content];
    self.tabBar = [[UIView alloc] init];
    self.tabBar.backgroundColor = self.darkTheme ? [UIColor colorWithRed:.10 green:.15 blue:.14 alpha:1] : [UIColor colorWithRed:.91 green:.94 blue:.93 alpha:1];
    [root addSubview:self.tabBar];
    self.tabIndicator=[[UIView alloc] init];self.tabIndicator.userInteractionEnabled=NO;self.tabIndicator.backgroundColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.16];self.tabIndicator.layer.cornerRadius=16;[self.tabBar addSubview:self.tabIndicator];
    self.tabButtons = [NSMutableArray array];
    NSArray *titles = @[LSL(@"Получить"), LSL(@"Отправить"), LSL(@"Настройки")]; NSArray *icons = @[@"receive", @"send", @"settings"];
    for (NSInteger i=0;i<3;i++) {
        UIButton *b=[self button:titles[i] icon:nil action:@selector(selectTab:)]; b.tag=i;
        UIImageView *icon=[[UIImageView alloc] initWithImage:LSIcon(icons[i], LSTextColor(self.darkTheme),24)]; icon.tag=100; icon.contentMode=UIViewContentModeCenter;
        [b addSubview:icon]; [self.tabBar addSubview:b]; [self.tabButtons addObject:b];
    }
    self.selectionButtons=[NSMutableArray array];
    UILabel *title=[self label:LSL(@"Выборка") size:20]; title.tag=200; [self.content addSubview:title];
    NSArray *selectTitles=@[LSL(@"Медиа"), LSL(@"Текст"), LSL(@"Файл")];
    NSArray *selectIcons=@[@"media", @"text", @"file"];
    for (NSInteger i=0;i<3;i++) {
        UIView *card=[self card]; UIButton *b=[self button:nil icon:nil action:@selector(selectSource:)]; b.tag=i; b.accessibilityLabel=selectTitles[i];
        UILabel *caption=[self label:selectTitles[i] size:14];caption.tag=101;caption.textAlignment=NSTextAlignmentCenter;caption.textColor=LSAccent(self.accentIndex);[b addSubview:caption];
        UIImageView *icon=[[UIImageView alloc] initWithImage:LSIcon(selectIcons[i],LSAccent(self.accentIndex),21)]; icon.tag=100; [b addSubview:icon];
        b.frame=CGRectMake(0,0,80,64); b.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [card addSubview:b]; [self.content addSubview:card]; [self.selectionButtons addObject:card];
    }
    self.selectionCard=[self card]; [self.content addSubview:self.selectionCard];
    self.selectionLabel=[self label:@"" size:12];self.selectionLabel.numberOfLines=1;self.selectionLabel.lineBreakMode=NSLineBreakByTruncatingMiddle; [self.selectionCard addSubview:self.selectionLabel];
    UIButton *clear=[self button:@"×" icon:nil action:@selector(clearSelection)]; clear.tag=300; clear.titleLabel.font=[UIFont systemFontOfSize:25]; [self.selectionCard addSubview:clear];
    self.devicesTitle=[self label:LSL(@"Устройства поблизости") size:17];self.devicesTitle.numberOfLines=1;self.devicesTitle.adjustsFontSizeToFitWidth=YES;self.devicesTitle.minimumScaleFactor=.8; [self.content addSubview:self.devicesTitle];
    self.scanButton=[self button:nil icon:@"refresh" action:@selector(scanAgain)]; [self.content addSubview:self.scanButton];
    self.hostField=[[UITextField alloc] init]; self.hostField.text=[[NSUserDefaults standardUserDefaults] stringForKey:@"lastHost"];
    self.hostField.placeholder=LSL(@"IP получателя"); self.hostField.font=[UIFont systemFontOfSize:13]; self.hostField.textColor=LSTextColor(self.darkTheme);
    self.hostField.backgroundColor=self.darkTheme ? [UIColor colorWithWhite:.18 alpha:1] : [UIColor whiteColor];
    UIView *accessory=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,40)]; accessory.backgroundColor=LSBackground(self.darkTheme);
    UIButton *done=[self button:LSL(@"Готово") icon:nil action:@selector(dismissKeyboard)]; done.frame=CGRectMake(230,0,80,40); done.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin; [accessory addSubview:done]; self.hostField.inputAccessoryView=accessory;
    self.hostField.layer.cornerRadius=9; self.hostField.keyboardType=UIKeyboardTypeNumbersAndPunctuation; self.hostField.delegate=self;
    UIView *padding=[[UIView alloc] initWithFrame:CGRectMake(0,0,10,20)]; self.hostField.leftView=padding; self.hostField.leftViewMode=UITextFieldViewModeAlways; [self.content addSubview:self.hostField];
    UIButton *send=[self button:LSL(@"Отправить") icon:nil action:@selector(sendSelected)]; send.tag=201;send.backgroundColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.14];send.layer.cornerRadius=9;[self.content addSubview:send];
    UIButton *manual=[self button:LSL(@"IP вручную") icon:nil action:@selector(toggleManualHost)];manual.tag=202;manual.titleLabel.font=[UIFont systemFontOfSize:12];[self.content addSubview:manual];
    self.table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.table.dataSource=self; self.table.delegate=self;
    self.table.backgroundColor=[UIColor clearColor]; self.table.separatorStyle=UITableViewCellSeparatorStyleNone; self.table.rowHeight=65; self.table.scrollEnabled=NO; [self.content addSubview:self.table];
    self.emptyLabel=[self label:LSL(@"Ищем устройства…\nОткройте LocalSend на получателе.\nОба устройства должны быть в одной Wi-Fi сети.") size:13];
    self.emptyLabel.textAlignment=NSTextAlignmentCenter; self.emptyLabel.textColor=[UIColor grayColor]; [self.content addSubview:self.emptyLabel];
    self.statusLabel=[self label:LSL(@"Выберите файл, затем получателя") size:12]; self.statusLabel.textAlignment=NSTextAlignmentCenter; self.statusLabel.textColor=LSAccent(self.accentIndex); [self.content addSubview:self.statusLabel];
    self.receivePanel=[[UIView alloc] init]; [self.content addSubview:self.receivePanel];
    UIImageView *logo=[[UIImageView alloc] initWithImage:LSIcon(@"logo",LSAccent(self.accentIndex),160)]; logo.tag=10; [self.receivePanel addSubview:logo];
    UILabel *alias=[self label:self.deviceAlias size:27]; alias.tag=11; alias.textAlignment=NSTextAlignmentCenter; alias.adjustsFontSizeToFitWidth=YES; alias.minimumScaleFactor=.6; [self.receivePanel addSubview:alias];
    UILabel *notice=[self label:LSL(@"Готов к получению файлов\nОткройте LocalSend на другом устройстве") size:14]; notice.tag=12; notice.textAlignment=NSTextAlignmentCenter; notice.textColor=[UIColor grayColor]; [self.receivePanel addSubview:notice];
    UIButton *go=[self button:LSL(@"Выбрать файл и отправить") icon:nil action:@selector(openSend)]; go.tag=13; go.layer.cornerRadius=19; go.layer.borderWidth=1; go.layer.borderColor=LSAccent(self.accentIndex).CGColor; [self.receivePanel addSubview:go];
    UIButton *history=[self button:nil icon:@"history" action:@selector(showHistory)]; history.tag=14; [self.receivePanel addSubview:history];
    UIButton *info=[self button:nil icon:@"info" action:@selector(showInfo)]; info.tag=15; [self.receivePanel addSubview:info];
    [self buildSettings]; if(self.receiveOverlay){[root addSubview:self.receiveOverlay];[self drawReceiveOverlay];} [self layoutInterface];
}
- (void)buildSettings {
    self.settingsPanel=[[UIView alloc] init]; [self.content addSubview:self.settingsPanel];
    UILabel *title=[self label:LSL(@"Настройки") size:25]; title.frame=CGRectMake(0,18,280,36); title.tag=20; title.textAlignment=NSTextAlignmentCenter; [self.settingsPanel addSubview:title];
    UIView *general=[self card]; general.tag=21; [self.settingsPanel addSubview:general];
    UILabel *heading=[self label:LSL(@"Общие") size:20]; heading.frame=CGRectMake(16,14,200,30); [general addSubview:heading];
    NSArray *names=@[LSL(@"Тема"), LSL(@"Цвет"), LSL(@"Анимации"), LSL(@"Язык")];
    for (NSInteger i=0;i<4;i++) {
        UILabel *label=[self label:names[i] size:15]; label.tag=140+i;label.frame=CGRectMake(16,60+i*58,95,38); [general addSubview:label];
        if(i<2){ NSString *value=i==0?(self.darkTheme?LSL(@"Тёмная ▾"):LSL(@"Светлая ▾")) : (@[@"LocalSend ▾",LSL(@"Синий ▾"),LSL(@"Лиловый ▾")])[self.accentIndex];
            UIButton *b=[self button:value icon:nil action:i==0?@selector(toggleTheme):@selector(changeColor)]; b.tag=30+i; b.layer.cornerRadius=8;
            b.backgroundColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.14]; [general addSubview:b];
        } else if(i==2) { LSFlatSwitch *toggle=[[LSFlatSwitch alloc] init]; toggle.tag=32; toggle.accessibilityLabel=LSL(@"Анимации"); toggle.on=self.animations;toggle.animationsEnabled=self.animations; toggle.onTintColor=LSAccent(self.accentIndex); [toggle addTarget:self action:@selector(toggleAnimations:) forControlEvents:UIControlEventValueChanged]; [general addSubview:toggle]; }
        else {NSString *preference=LSLanguagePreference();NSString *language=[preference isEqual:@"system"]?LSL(@"Системный"):(@{@"ru":@"Русский",@"en":@"English",@"uk":@"Українська"})[preference];
            UIButton *choose=[self button:[NSString stringWithFormat:@"%@ ▾",LSL(language)] icon:nil action:@selector(chooseLanguage)];choose.tag=34;choose.titleLabel.font=[UIFont systemFontOfSize:13];choose.layer.cornerRadius=8;choose.backgroundColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.14];[general addSubview:choose];}
    }
    UIView *device=[self card]; device.tag=22; [self.settingsPanel addSubview:device];
    UILabel *deviceTitle=[self label:LSL(@"Устройство") size:20]; deviceTitle.frame=CGRectMake(16,14,220,28); [device addSubview:deviceTitle];
    UILabel *name=[self label:LSL(@"Имя устройства") size:14]; name.frame=CGRectMake(16,49,180,25); [device addSubview:name];
    UIButton *alias=[self button:self.deviceAlias icon:nil action:@selector(editAlias)]; alias.tag=33; alias.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft; alias.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail; [device addSubview:alias];
    UILabel *about=[self label:LSL(@"LocalSend 6 · 0.5.7\nСовместимо с iOS 6 и новее\nTLS 1.2 / 1.3") size:12]; about.tag=23; about.textAlignment=NSTextAlignmentCenter; about.textColor=[UIColor grayColor]; [self.settingsPanel addSubview:about];
    UILabel *credit=[self label:@"made by anazerka" size:13];credit.tag=24;credit.textAlignment=NSTextAlignmentCenter;[self.settingsPanel addSubview:credit];
    UIButton *github=[self button:@"github.com/theanazerka/unlocalsend" icon:nil action:@selector(openGitHub)];github.tag=25;github.titleLabel.font=[UIFont systemFontOfSize:11];github.accessibilityLabel=LSL(@"Открыть проект на GitHub");[self.settingsPanel addSubview:github];
}
- (void)layoutInterface {
    CGRect bounds=self.window.rootViewController.view.bounds; CGFloat w=bounds.size.width;
    BOOL modern = [[[UIDevice currentDevice] systemVersion] floatValue]>=7;
    CGFloat top=modern?20:0; CGFloat h=bounds.size.height-top-72;
    self.content.frame=CGRectMake(0,top,w,h); self.tabBar.frame=CGRectMake(0,bounds.size.height-72,w,72);
    for(NSInteger i=0;i<3;i++){ UIButton *b=self.tabButtons[i]; b.frame=CGRectMake(i*w/3,0,w/3,72); UIImageView *icon=(id)[b viewWithTag:100]; icon.frame=CGRectMake((w/3-56)/2,7,56,32);
        icon.backgroundColor=[UIColor clearColor];
        [b setTitleColor:i==self.activeTab?LSTextColor(self.darkTheme):[UIColor grayColor] forState:UIControlStateNormal]; b.titleEdgeInsets=UIEdgeInsetsMake(39,0,0,0);
    }
    self.tabIndicator.frame=CGRectMake(self.activeTab*w/3+(w/3-56)/2,7,56,32);
    BOOL send=self.activeTab==1;
    for(UIView *v in self.content.subviews) v.hidden=!send;
    self.receivePanel.hidden=self.activeTab!=0; self.settingsPanel.hidden=self.activeTab!=2;
    CGFloat margin=14, gap=9, cardW=(w-2*margin-2*gap)/3;
    [self.content viewWithTag:200].frame=CGRectMake(margin,14,w-28,28);
    for(NSInteger i=0;i<3;i++){ UIView *card=self.selectionButtons[i]; card.frame=CGRectMake(margin+(i%3)*(cardW+gap),51+(i/3)*73,cardW,64); UIButton *b=card.subviews[0]; b.frame=card.bounds; [b viewWithTag:100].frame=CGRectMake((cardW-21)/2,9,21,21); [b viewWithTag:101].frame=CGRectMake(3,35,cardW-6,23); }
    CGFloat y=130;
    self.selectionCard.hidden=!send || !self.selectedFile.length;
    if(self.selectedFile.length){ self.selectionCard.frame=CGRectMake(margin,y,w-28,43); self.selectionLabel.frame=CGRectMake(12,4,w-76,35); self.selectionLabel.text=[NSString stringWithFormat:LSL(@"Выбрано: %@"),self.selectedFile.lastPathComponent]; [self.selectionCard viewWithTag:300].frame=CGRectMake(w-65,1,32,40); y+=55; }
    self.devicesTitle.text=self.browsingFiles?LSL(@"Файлы приложения"):LSL(@"Устройства поблизости");
    self.devicesTitle.frame=CGRectMake(margin,y,w-77,28); self.scanButton.frame=CGRectMake(w-55,y-5,42,38); y+=38;
    [self.content viewWithTag:202].hidden=!send || self.browsingFiles;
    self.hostField.hidden=!send || self.browsingFiles || !self.manualHostVisible; [self.content viewWithTag:201].hidden=self.hostField.hidden;
    if(!self.browsingFiles && self.manualHostVisible){ self.hostField.frame=CGRectMake(margin,y,w-132,35); [self.content viewWithTag:201].frame=CGRectMake(w-112,y,100,35); y+=44; }
    NSInteger rows=self.browsingFiles?self.files.count:self.peers.count;
    self.table.frame=CGRectMake(margin,y,w-28,rows*65); y+=rows*65;
    self.emptyLabel.hidden=!send || rows>0; self.emptyLabel.text=self.browsingFiles?LSL(@"Файлов пока нет.\nДобавьте фото или скопируйте файлы\nчерез iTunes → File Sharing."):LSL(@"Ищем устройства…\nОткройте LocalSend на получателе.\nОба устройства должны быть в одной Wi-Fi сети.");
    if(!rows){self.emptyLabel.frame=CGRectMake(margin,y+8,w-28,90); y+=106;}
    if(!self.browsingFiles){[self.content viewWithTag:202].frame=CGRectMake(margin,y+5,w-28,30);y+=37;}
    self.statusLabel.frame=CGRectMake(margin,y+7,w-28,40); y+=60;
    self.receivePanel.frame=CGRectMake(0,0,w,h);
    [self.receivePanel viewWithTag:10].frame=CGRectMake((w-130)/2,MAX(70,h*.21),130,130);
    [self.receivePanel viewWithTag:11].frame=CGRectMake(14,MAX(70,h*.21)+154,w-28,46);
    [self.receivePanel viewWithTag:12].frame=CGRectMake(24,MAX(70,h*.21)+207,w-48,48);
    [self.receivePanel viewWithTag:13].frame=CGRectMake(28,MAX(h-65,345),w-56,40);
    [self.receivePanel viewWithTag:14].frame=CGRectMake(w-91,8,40,40); [self.receivePanel viewWithTag:15].frame=CGRectMake(w-49,8,40,40);
    [self.settingsPanel viewWithTag:20].frame=CGRectMake(0,8,w,36);
    CGFloat rowHeight=h>=460?50:54;
    UIView *general=[self.settingsPanel viewWithTag:21];general.frame=CGRectMake(margin,58,w-28,62+4*rowHeight);
    for(NSInteger i=0;i<4;i++){
        [general viewWithTag:140+i].frame=CGRectMake(16,54+i*rowHeight,95,38);
        NSInteger tag=i==3?34:30+i;
        if(i==2)[general viewWithTag:tag].frame=CGRectMake(w*.43+8,58+i*rowHeight,52,31);
        else [general viewWithTag:tag].frame=CGRectMake(w*.43,54+i*rowHeight,w-44-w*.43,40);
    }
    UIView *device=[self.settingsPanel viewWithTag:22];device.frame=CGRectMake(margin,CGRectGetMaxY(general.frame)+18,w-28,119);[device viewWithTag:33].frame=CGRectMake(16,77,w-60,30);
    [self.settingsPanel viewWithTag:23].frame=CGRectMake(14,CGRectGetMaxY(device.frame)+14,w-28,54);
    CGFloat settingsHeight=0;
    CGFloat footerY=CGRectGetMaxY([self.settingsPanel viewWithTag:23].frame)+8;
    [self.settingsPanel viewWithTag:24].frame=CGRectMake(14,footerY,w-28,24);
    [self.settingsPanel viewWithTag:25].frame=CGRectMake(14,footerY+24,w-28,40);
    settingsHeight=footerY+76;
    self.settingsPanel.frame=CGRectMake(0,0,w,settingsHeight);
    self.content.contentSize=CGSizeMake(w,self.activeTab==1?MAX(h,y):(self.activeTab==2?MAX(h,settingsHeight):MAX(h,405)));
    [self updateLogoAnimation];
    [self layoutReceiveOverlay];
}
- (void)dismissKeyboard { [self.hostField resignFirstResponder]; }
- (void)keyboardChanged:(NSNotification *)notification {
    if([notification.name isEqual:UIKeyboardWillHideNotification]) { self.content.contentInset=UIEdgeInsetsZero; self.content.scrollIndicatorInsets=UIEdgeInsetsZero; return; }
    CGRect keyboard=[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboard=[self.window.rootViewController.view convertRect:keyboard fromView:nil];
    CGFloat overlap=MAX(0,CGRectGetMaxY(self.content.frame)-keyboard.origin.y);
    self.content.contentInset=UIEdgeInsetsMake(0,0,overlap+10,0); self.content.scrollIndicatorInsets=self.content.contentInset;
    if(self.hostField.isFirstResponder) [self.content scrollRectToVisible:CGRectInset(self.hostField.frame,0,-12) animated:self.animations];
}
- (void)selectTab:(UIButton *)button {
    [self.hostField resignFirstResponder];if(self.activeTab==button.tag)return;
    self.activeTab=button.tag;self.content.contentOffset=CGPointZero;[self layoutInterface];
}
- (void)openSend {[self selectTab:self.tabButtons[1]];}
- (void)clearSelection { self.selectedFile=nil; [self layoutInterface]; }
- (void)selectSource:(UIButton *)button {
    if(button.tag==0) [self choosePhoto];
    else if(button.tag==1){ UIAlertView *a=[[UIAlertView alloc] initWithTitle:LSL(@"Отправить текст") message:LSL(@"Текст сохранится в файл") delegate:self cancelButtonTitle:LSL(@"Отмена") otherButtonTitles:LSL(@"Добавить"),nil]; a.alertViewStyle=UIAlertViewStylePlainTextInput; a.tag=41; [a show]; }
    else if(button.tag==2)[self chooseFile];
}
- (void)chooseFile {
    __weak AppDelegate *weakSelf=self;
    LSFilesystemPicker *picker=[[LSFilesystemPicker alloc] initWithDirectory:@"/" documents:[self documentsPath] dark:self.darkTheme accent:self.accentIndex animations:self.animations selection:^(NSURL *url){[weakSelf importChosenFileAtURL:url];}];
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:picker];
    navigation.navigationBar.tintColor=LSAccent(self.accentIndex);navigation.toolbar.tintColor=LSAccent(self.accentIndex);
    [self.window.rootViewController presentViewController:navigation animated:self.animations completion:nil];
}
- (void)importChosenFileAtURL:(NSURL *)url {
    if(!url.isFileURL)return;
    NSString *localRoot=[[self documentsPath] stringByResolvingSymlinksInPath];NSString *resolved=[url.path stringByResolvingSymlinksInPath];
    if([resolved hasPrefix:[localRoot stringByAppendingString:@"/"]]){self.selectedFile=[resolved substringFromIndex:localRoot.length+1];self.browsingFiles=NO;[self layoutInterface];[self showMessage:LSL(@"Файл выбран. Нажмите на получателя.")];return;}
    url=[NSURL fileURLWithPath:resolved];
    [self showMessage:LSL(@"Импорт файла…")];
    NSString *root=[self documentsPath];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
        __block NSError *copyError=nil;NSError *coordinationError=nil;__block NSString *name=nil;
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL){
            BOOL directory=NO;if(![[NSFileManager defaultManager] fileExistsAtPath:readURL.path isDirectory:&directory] || directory){copyError=[NSError errorWithDomain:@"LocalSend" code:1 userInfo:@{NSLocalizedDescriptionKey:LSL(@"Выберите обычный файл.")}];return;}
            name=url.lastPathComponent.length?url.lastPathComponent:@"File";
            NSString *destination=[root stringByAppendingPathComponent:name];
            if([[NSFileManager defaultManager] fileExistsAtPath:destination]){NSString *stem=[name stringByDeletingPathExtension];NSString *ext=name.pathExtension;name=[NSString stringWithFormat:@"%@-%@",stem,[[NSUUID UUID] UUIDString]];if(ext.length)name=[name stringByAppendingPathExtension:ext];destination=[root stringByAppendingPathComponent:name];}
            [[NSFileManager defaultManager] copyItemAtPath:readURL.path toPath:destination error:&copyError];
        }];
        NSError *error=coordinationError?:copyError;
        dispatch_async(dispatch_get_main_queue(),^{
            if(error || !name.length){[[[UIAlertView alloc] initWithTitle:LSL(@"Не удалось импортировать файл") message:error.localizedDescription?:LSL(@"Файл недоступен.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];return;}
            self.selectedFile=name;self.browsingFiles=NO;[self layoutInterface];[self showMessage:LSL(@"Файл выбран. Нажмите на получателя.")];
        });
    });
}
- (void)addText:(NSString *)text {
    NSString *name=[NSString stringWithFormat:@"Text-%.0f.txt",[[NSDate date] timeIntervalSince1970]];
    NSError *error=nil; if(![text writeToFile:[[self documentsPath] stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:&error]){[self showMessage:error.localizedDescription];return;}
    self.selectedFile=name; self.browsingFiles=NO; [self refreshFiles]; [self showMessage:LSL(@"Текст добавлен. Выберите получателя.")];
}
- (void)scanAgain {
    self.browsingFiles=NO; [self.table reloadData]; [self layoutInterface];
    if(self.discoverySocket>=0){ NSDictionary *j=@{@"alias":self.deviceAlias,@"version":@"2.0",@"deviceModel":@"iPhone",@"deviceType":@"mobile",@"fingerprint":self.localFingerprint?:@"",@"port":@53317,@"protocol":@"https",@"download":@NO,@"announce":@YES}; NSData *d=[NSJSONSerialization dataWithJSONObject:j options:0 error:nil]; struct sockaddr_in dst; memset(&dst,0,sizeof(dst)); dst.sin_len=sizeof(dst); dst.sin_family=AF_INET; dst.sin_port=htons(53317); dst.sin_addr.s_addr=inet_addr("224.0.0.167"); sendto(self.discoverySocket,d.bytes,d.length,0,(struct sockaddr *)&dst,sizeof(dst)); } else [self startDiscovery];
    [self showMessage:LSL(@"Поиск устройств обновлён")];
    if(self.animations){ [UIView animateWithDuration:.25 animations:^{self.scanButton.transform=CGAffineTransformMakeRotation(M_PI);} completion:^(BOOL done){self.scanButton.transform=CGAffineTransformIdentity;}]; }
}
- (void)sendSelected {
    NSString *host=[self.hostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(!self.selectedFile.length){[self showMessage:LSL(@"Сначала выберите фото, текст или файл")];return;}
    if(!host.length){[self showMessage:LSL(@"Выберите устройство или введите IP")];return;}
    [[NSUserDefaults standardUserDefaults] setObject:host forKey:@"lastHost"]; [self.hostField resignFirstResponder]; [self sendFile:self.selectedFile toHost:host];
}
- (void)chooseLanguage {
    UIActionSheet *sheet=[[UIActionSheet alloc] initWithTitle:LSL(@"Язык") delegate:self cancelButtonTitle:LSL(@"Отмена") destructiveButtonTitle:nil otherButtonTitles:LSL(@"Системный"),@"Русский",@"English",@"Українська",nil];sheet.tag=60;[sheet showInView:self.window.rootViewController.view];
}
- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if(sheet.tag!=60 || index<0 || index>=4)return;LSSetLanguage((@[@"system",@"ru",@"en",@"uk"])[index]);[self buildInterface];
}
- (void)openGitHub { [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/theanazerka/unlocalsend"]]; }
- (void)toggleTheme { self.darkTheme=!self.darkTheme; [[NSUserDefaults standardUserDefaults] setBool:self.darkTheme forKey:@"darkTheme"]; [self buildInterface]; }
- (void)changeColor { self.accentIndex=(self.accentIndex+1)%3; [[NSUserDefaults standardUserDefaults] setInteger:self.accentIndex forKey:@"accentIndex"]; [self buildInterface]; }
- (void)toggleAnimations:(LSFlatSwitch *)toggle { self.animations=toggle.on;toggle.animationsEnabled=self.animations; [[NSUserDefaults standardUserDefaults] setBool:self.animations forKey:@"animations"]; [self updateLogoAnimation]; }
- (void)editAlias { UIAlertView *a=[[UIAlertView alloc] initWithTitle:LSL(@"Имя устройства") message:nil delegate:self cancelButtonTitle:LSL(@"Отмена") otherButtonTitles:LSL(@"Сохранить"),nil]; a.alertViewStyle=UIAlertViewStylePlainTextInput; a.tag=42; [a textFieldAtIndex:0].text=self.deviceAlias; [a show]; }
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index { if(index!=1)return; NSString *text=[[alert textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; if(!text.length)return; if(alert.tag==41)[self addText:text]; else if(alert.tag==42){self.deviceAlias=text;self.receiver.alias=text;[[NSUserDefaults standardUserDefaults] setObject:text forKey:@"deviceAlias"];[self buildInterface];} }
- (void)showHistory { NSString *text=self.history.count?[self.history componentsJoinedByString:@"\n\n"]:LSL(@"Пока нет завершённых передач"); [[[UIAlertView alloc] initWithTitle:LSL(@"История отправок") message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; }
- (void)showInfo {
    NSMutableArray *addresses=[NSMutableArray array];struct ifaddrs *interfaces=NULL;
    if(getifaddrs(&interfaces)==0){for(struct ifaddrs *i=interfaces;i;i=i->ifa_next){if(!i->ifa_addr || !(i->ifa_flags & IFF_UP))continue;int family=i->ifa_addr->sa_family;if(family!=AF_INET && family!=AF_INET6)continue;char host[NI_MAXHOST];socklen_t length=family==AF_INET?sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
            if(getnameinfo(i->ifa_addr,length,host,sizeof(host),NULL,0,NI_NUMERICHOST)==0){NSString *address=[NSString stringWithUTF8String:host];NSString *line=[NSString stringWithFormat:@"%@ · %@",[NSString stringWithUTF8String:i->ifa_name],address];if(![addresses containsObject:line])[addresses addObject:line];}
        }freeifaddrs(interfaces);}
    NSString *message=[NSString stringWithFormat:LSL(@"Имя: %@\n\nIP-адреса:\n%@\n\nHTTPS / TCP: %lu (%@)\nОбнаружение / UDP: 53317 (%@)\nMulticast: 224.0.0.167"),self.deviceAlias,addresses.count?[addresses componentsJoinedByString:@"\n"]:LSL(@"Нет активных адресов"),(unsigned long)self.receiver.port,self.receiver.ready?LSL(@"работает"):LSL(@"не запущен"),self.discoverySocket>=0?LSL(@"работает"):LSL(@"не запущено")];
    [[[UIAlertView alloc] initWithTitle:LSL(@"Это устройство") message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}
- (void)toggleManualHost {self.manualHostVisible=!self.manualHostVisible;if(!self.manualHostVisible)[self.hostField resignFirstResponder];[self layoutInterface];if(self.manualHostVisible)[self.content scrollRectToVisible:self.hostField.frame animated:self.animations];}


- (NSString *)documentsPath { return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]; }
- (void)refreshFiles {
    NSMutableArray *items=[NSMutableArray array]; NSString *root=[self documentsPath];
    for(NSString *name in [[NSFileManager defaultManager] enumeratorAtPath:root]) { BOOL directory=NO; [[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:name] isDirectory:&directory]; if(!directory && ![name isEqual:@"LastTransferError.txt"] && ![name hasPrefix:@"."]) [items addObject:name]; }
    self.files=[items sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; [self.table reloadData]; [self layoutInterface];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.browsingFiles?self.files.count:self.peers.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"LocalSendRow"];
    CGFloat width=tableView.bounds.size.width;
    if(!cell){
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LocalSendRow"];cell.backgroundColor=[UIColor clearColor];cell.selectionStyle=UITableViewCellSelectionStyleNone;
        UIView *card=[self card];card.tag=900;card.frame=CGRectMake(1,4,width-2,55);card.autoresizingMask=UIViewAutoresizingFlexibleWidth;[cell.contentView addSubview:card];
        UIImageView *image=[[UIImageView alloc] init];image.tag=903;image.frame=CGRectMake(12,15,25,25);[card addSubview:image];
        UILabel *name=[self label:nil size:15];name.tag=901;name.frame=CGRectMake(49,5,width-81,25);name.numberOfLines=1;name.lineBreakMode=NSLineBreakByTruncatingTail;name.autoresizingMask=UIViewAutoresizingFlexibleWidth;[card addSubview:name];
        UILabel *detail=[self label:nil size:11];detail.tag=902;detail.frame=CGRectMake(49,30,width-81,18);detail.textColor=[UIColor grayColor];detail.numberOfLines=1;detail.lineBreakMode=NSLineBreakByTruncatingMiddle;detail.autoresizingMask=UIViewAutoresizingFlexibleWidth;[card addSubview:detail];
        UILabel *arrow=[self label:@"›" size:25];arrow.textColor=LSAccent(self.accentIndex);arrow.frame=CGRectMake(width-27,12,20,30);arrow.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;[card addSubview:arrow];
    }
    NSString *title,*subtitle,*icon;
    if(self.browsingFiles){NSString *name=self.files[indexPath.row];title=name.lastPathComponent;subtitle=[name stringByDeletingLastPathComponent].length?name:LSL(@"Нажмите, чтобы выбрать");icon=@"file";}
    else{NSDictionary *peer=self.peers[indexPath.row];title=peer[@"alias"];subtitle=[NSString stringWithFormat:@"%@ · %@",peer[@"ip"],[peer[@"protocol"] uppercaseString]];icon=@"device";}
    ((UILabel *)[cell.contentView viewWithTag:901]).text=title;
    ((UILabel *)[cell.contentView viewWithTag:902]).text=subtitle;
    ((UIImageView *)[cell.contentView viewWithTag:903]).image=LSIcon(icon,LSAccent(self.accentIndex),25);
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:self.animations];
    if(self.browsingFiles){self.selectedFile=self.files[indexPath.row];self.browsingFiles=NO;[self.table reloadData];[self layoutInterface];[self showMessage:LSL(@"Файл выбран. Нажмите на получателя.")];}
    else { NSDictionary *peer=self.peers[indexPath.row]; self.hostField.text=peer[@"ip"]; if(self.selectedFile.length)[self sendSelected]; else [self showMessage:LSL(@"Устройство выбрано. Добавьте фото, текст или файл.")]; }
}
- (void)showMessage:(NSString *)message { dispatch_async(dispatch_get_main_queue(), ^{ self.statusLabel.text = message; }); }

- (void)showTransferFailure:(NSString *)message stage:(NSString *)stage URL:(NSURL *)URL {
    NSString *details = [NSString stringWithFormat:@"%@\n%@\n%@", stage, message, URL.absoluteString];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.sending=NO; [self refreshIdleTimer]; self.statusLabel.text = [stage stringByAppendingString:LSL(@": ошибка")];
        [details writeToFile:[[self documentsPath] stringByAppendingPathComponent:@"LastTransferError.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [[[UIAlertView alloc] initWithTitle:LSL(@"Ошибка передачи") message:details delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    });
}

- (void)choosePhoto {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) { [self showMessage:LSL(@"Библиотека фотографий недоступна")]; return; }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init]; picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;picker.mediaTypes=[UIImagePickerController availableMediaTypesForSourceType:picker.sourceType]; picker.delegate = self; [self.window.rootViewController presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSURL *movie=info[UIImagePickerControllerMediaURL];if([movie isKindOfClass:[NSURL class]]){[picker dismissViewControllerAnimated:self.animations completion:^{[self importChosenFileAtURL:movie];}];return;}
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage]; NSData *data = UIImageJPEGRepresentation(image, 0.92); NSString *stamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]]; NSString *name = [NSString stringWithFormat:@"Photo-%@.jpg", stamp]; NSString *path = [[self documentsPath] stringByAppendingPathComponent:name]; NSError *error = nil;
    BOOL saved = data && [data writeToFile:path options:NSDataWritingAtomic error:&error]; [picker dismissViewControllerAnimated:YES completion:nil];
    if (!saved) { [self showMessage:error ? [error localizedDescription] : LSL(@"Не удалось сохранить фотографию")]; return; }
    self.selectedFile=name; self.browsingFiles=NO; [self refreshFiles]; [self showMessage:LSL(@"Фото выбрано. Нажмите на получателя.")];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

- (void)startDiscovery {
    if (self.discovering) return; self.discovering = YES;
    int s = socket(AF_INET, SOCK_DGRAM, 0); if (s < 0) { self.discovering = NO; return; } self.discoverySocket = s;
    int yes = 1; setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)); struct sockaddr_in local; memset(&local, 0, sizeof(local)); local.sin_len = sizeof(local); local.sin_family = AF_INET; local.sin_port = htons(53317); local.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(s, (struct sockaddr *)&local, sizeof(local)) != 0) { close(s); self.discoverySocket = -1; self.discovering = NO; [self showMessage:LSL(@"Не удалось открыть UDP 53317; используйте IP вручную")]; return; }
    struct ip_mreq m; m.imr_multiaddr.s_addr = inet_addr("224.0.0.167"); m.imr_interface.s_addr = htonl(INADDR_ANY); setsockopt(s, IPPROTO_IP, IP_ADD_MEMBERSHIP, &m, sizeof(m));
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while (self.discovering) { char buf[4096]; struct sockaddr_in from; socklen_t len = sizeof(from); ssize_t n = recvfrom(s, buf, sizeof(buf)-1, 0, (struct sockaddr *)&from, &len); if (n <= 0) continue; buf[n] = 0; NSData *d = [NSData dataWithBytes:buf length:(NSUInteger)n]; NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil]; if (![json isKindOfClass:[NSDictionary class]]) continue;
            if ([[json objectForKey:@"fingerprint"] isEqual:self.localFingerprint]) continue;
            if ([[json objectForKey:@"announce"] boolValue]) { NSDictionary *answer = @{ @"alias": self.deviceAlias, @"version": @"2.0", @"deviceModel": @"iPhone", @"deviceType": @"mobile", @"fingerprint": self.localFingerprint ?: @"", @"port": @53317, @"protocol": @"https", @"download": @NO, @"announce": @NO }; NSData *answerData = [NSJSONSerialization dataWithJSONObject:answer options:0 error:nil]; sendto(s, [answerData bytes], [answerData length], 0, (struct sockaddr *)&from, len); }
            NSDictionary *peer = @{ @"ip": [NSString stringWithUTF8String:inet_ntoa(from.sin_addr)], @"port": [NSString stringWithFormat:@"%ld", (long)([[json objectForKey:@"port"] integerValue] ?: 53317)], @"alias": [json objectForKey:@"alias"] ?: [json objectForKey:@"deviceModel"] ?: @"LocalSend", @"protocol": [json objectForKey:@"protocol"] ?: @"http", @"fingerprint": [json objectForKey:@"fingerprint"] ?: @"" };
            dispatch_async(dispatch_get_main_queue(), ^{ [self addPeer:peer]; });
        }
    });
    NSDictionary *announce = @{ @"alias": self.deviceAlias, @"version": @"2.0", @"deviceModel": @"iPhone", @"deviceType": @"mobile", @"fingerprint": self.localFingerprint ?: @"", @"port": @53317, @"protocol": @"https", @"download": @NO, @"announce": @YES };
    NSData *payload = [NSJSONSerialization dataWithJSONObject:announce options:0 error:nil]; struct sockaddr_in dst; memset(&dst, 0, sizeof(dst)); dst.sin_len=sizeof(dst); dst.sin_family=AF_INET; dst.sin_port=htons(53317); dst.sin_addr.s_addr=inet_addr("224.0.0.167"); setsockopt(s, IPPROTO_IP, IP_MULTICAST_TTL, &(u_char){1}, sizeof(u_char)); sendto(s, [payload bytes], [payload length], 0, (struct sockaddr *)&dst, sizeof(dst)); [self showMessage:LSL(@"Ищем устройства… также можно ввести IP вручную")];
}

- (void)sendFile:(NSString *)name toHost:(NSString *)host {
    if(self.sending){[self showMessage:LSL(@"Дождитесь завершения текущей передачи")];return;}
    NSString *path = [[self documentsPath] stringByAppendingPathComponent:name]; NSData *data = [NSData dataWithContentsOfFile:path]; if (!data) { [self showMessage:LSL(@"Не удалось прочитать файл")]; return; }
    self.sending=YES; [self refreshIdleTimer]; self.statusLabel.text = LSL(@"Подключение к получателю…"); NSString *fid = [[NSUUID UUID] UUIDString]; NSString *port = @"53317"; NSString *scheme = @"https"; NSString *fingerprint = nil; for (NSDictionary *p in self.peers) if ([[p objectForKey:@"ip"] isEqual:host]) { port = [p objectForKey:@"port"]; scheme = [[p objectForKey:@"protocol"] isEqual:@"http"] ? @"http" : @"https"; fingerprint = [p objectForKey:@"fingerprint"]; break; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        LSConnection *connection = [[LSConnection alloc] init]; connection.expectedFingerprint = fingerprint;
        NSString *mime = @"application/octet-stream"; NSString *ext = [[name pathExtension] lowercaseString]; if ([ext isEqual:@"jpg"] || [ext isEqual:@"jpeg"]) mime = @"image/jpeg"; else if ([ext isEqual:@"png"]) mime = @"image/png"; else if ([ext isEqual:@"txt"]) mime = @"text/plain";else if([@[@"mp4",@"m4v"] containsObject:ext])mime=@"video/mp4";else if([ext isEqual:@"mov"])mime=@"video/quicktime";
        NSDictionary *info = @{ @"alias": self.deviceAlias, @"version": @"2.0", @"deviceModel": @"iPhone", @"deviceType": @"mobile", @"fingerprint": self.localFingerprint ?: @"", @"port": @53317, @"protocol": @"https", @"download": @NO };
        NSDictionary *file = @{ @"id": fid, @"fileName": name.lastPathComponent, @"size": @([data length]), @"fileType": mime };
        NSDictionary *body = @{ @"info": info, @"files": @{ fid: file } };
        NSURL *prepareURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%@/api/localsend/v2/prepare-upload", scheme, host, port]]; NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:prepareURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:120]; [request setHTTPMethod:@"POST"]; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [request setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];
        NSError *err = nil; NSURLResponse *response = nil; NSData *reply = [scheme isEqual:@"https"] ? LSHTTPSRequestWithProgress(request, fingerprint, &response, &err, ^(NSString *stage,double fraction){ if([stage isEqual:@"waiting"])[self showMessage:LSL(@"Запрос отправлен. Ожидаем «Принять» на получателе…")]; }) : [connection sendRequest:request response:&response error:&err]; NSInteger code = [(NSHTTPURLResponse *)response statusCode]; NSDictionary *result = reply ? [NSJSONSerialization JSONObjectWithData:reply options:0 error:nil] : nil;
        if (err || code < 200 || code >= 300 || ![result objectForKey:@"sessionId"] || ![[result objectForKey:@"files"] objectForKey:fid]) { NSString *message = err ? [NSString stringWithFormat:@"%@ (%@ %ld)", err.localizedDescription, err.domain, (long)err.code] : [NSString stringWithFormat:LSL(@"Получатель отклонил запрос (HTTP %ld)"), (long)code]; [self showTransferFailure:message stage:LSL(@"Подготовка") URL:prepareURL]; return; }
        NSString *sid = [result objectForKey:@"sessionId"]; NSString *token = [[result objectForKey:@"files"] objectForKey:fid]; NSString *escapedSID = [sid stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; NSString *escapedToken = [token stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; NSString *escapedFID = [fid stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; NSURL *uploadURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:%@/api/localsend/v2/upload?sessionId=%@&fileId=%@&token=%@", scheme, host, port, escapedSID, escapedFID, escapedToken]]; NSMutableURLRequest *upload = [NSMutableURLRequest requestWithURL:uploadURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:180]; [upload setHTTPMethod:@"POST"]; [upload setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"]; [upload setHTTPBody:data]; response=nil; err=nil; if ([scheme isEqual:@"https"]) LSHTTPSRequestWithProgress(upload, fingerprint, &response, &err, ^(NSString *stage,double fraction){ [self showMessage:[stage isEqual:@"waiting"]?LSL(@"Файл отправлен. Подтверждение получателя…"):[NSString stringWithFormat:LSL(@"Отправка: %.0f%%"),fraction*100]]; }); else [connection sendRequest:upload response:&response error:&err]; code=[(NSHTTPURLResponse *)response statusCode]; if (!err && code >= 200 && code < 300) { dispatch_async(dispatch_get_main_queue(), ^{ self.sending=NO; [self refreshIdleTimer]; [self.history insertObject:[NSString stringWithFormat:@"%@ → %@",name.lastPathComponent,host] atIndex:0]; if(self.history.count>10)[self.history removeLastObject]; [[NSUserDefaults standardUserDefaults] setObject:self.history forKey:@"transferHistory"]; [self showMessage:[NSString stringWithFormat:LSL(@"Отправлено: %@"),name.lastPathComponent]]; }); } else { NSString *message = err ? [NSString stringWithFormat:@"%@ (%@ %ld)", err.localizedDescription, err.domain, (long)err.code] : [NSString stringWithFormat:@"HTTP %ld", (long)code]; [self showTransferFailure:message stage:LSL(@"Загрузка") URL:uploadURL]; }
    });
}
- (void)addPeer:(NSDictionary *)peer {
    if(![peer[@"ip"] isKindOfClass:[NSString class]])return;
    NSMutableDictionary *normalized=[peer mutableCopy]; normalized[@"alias"]=[peer[@"alias"] isKindOfClass:[NSString class]]?peer[@"alias"]:@"LocalSend";
    normalized[@"protocol"]=[peer[@"protocol"] isKindOfClass:[NSString class]]?peer[@"protocol"]:@"https"; normalized[@"port"]=[peer[@"port"] description]?:@"53317";
    NSUInteger index=NSNotFound;for(NSUInteger i=0;i<self.peers.count;i++)if([self.peers[i][@"ip"] isEqual:peer[@"ip"]]){index=i;break;}
    if(index!=NSNotFound && [self.peers[index] isEqualToDictionary:normalized])return;
    if(index==NSNotFound)[self.peers addObject:normalized];else self.peers[index]=normalized;
    if(!self.browsingFiles)[self.table reloadData];
    if(self.activeTab==1)[self layoutInterface];
}
- (void)refreshIdleTimer { [UIApplication sharedApplication].idleTimerDisabled=self.sending || self.photoImporter.importing || [@[@"offer",@"receiving"] containsObject:self.receiveState[@"phase"]?:@""]; }
- (void)updateLogoAnimation {
    UIView *logo=[self.receivePanel viewWithTag:10];
    if(self.activeTab==0 && self.animations && !self.receiveOverlay && self.receiver.ready){
        if(![logo.layer animationForKey:@"slowRotation"]){CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];a.fromValue=@0;a.toValue=@(2*M_PI);a.duration=25;a.repeatCount=HUGE_VALF;a.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];[logo.layer addAnimation:a forKey:@"slowRotation"];}
    }else [logo.layer removeAnimationForKey:@"slowRotation"];
}
- (NSString *)formatBytes:(long long)bytes { if(bytes<1024)return [NSString stringWithFormat:@"%lld B",bytes];if(bytes<1048576)return [NSString stringWithFormat:LSL(@"%.1f КБ"),bytes/1024.0];return [NSString stringWithFormat:LSL(@"%.1f МБ"),bytes/1048576.0]; }
- (void)receiverChanged:(NSDictionary *)state {
    BOOL changed=![self.receiveState[@"phase"] isEqual:state[@"phase"]] || ![self.receiveState[@"sessionId"] isEqual:state[@"sessionId"]];
    self.receiveState=state; [self refreshIdleTimer];
    if(!self.receiveOverlay){self.receiveOverlay=[[UIView alloc] init];[self.window.rootViewController.view addSubview:self.receiveOverlay];self.receiveTimer=[NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(updateReceiveTime) userInfo:nil repeats:YES];}
    if(changed)[self drawReceiveOverlay];else [self updateReceiveProgress];[self updateLogoAnimation];
    if(changed && [state[@"phase"] isEqual:@"complete"]){
        __weak AppDelegate *weakSelf=self;
        __block BOOL reportedPhotoError=NO;
        for(NSDictionary *file in state[@"items"])if([LSPhotoImporter isMediaFile:file])self.photoResults[file[@"path"]]=@"Сохранение в Фото…";
        [self.photoImporter enqueueFiles:state[@"items"] completion:^(NSString *path,NSError *error){
            AppDelegate *app=weakSelf;if(!app)return;app.photoResults[path]=error?@"Не сохранено в Фото":@"Сохранено в Фото";[app updateReceiveProgress];[app refreshIdleTimer];
            if(error && !reportedPhotoError){reportedPhotoError=YES;[[[UIAlertView alloc] initWithTitle:LSL(@"Файл получен, но не сохранён в Фото") message:[NSString stringWithFormat:LSL(@"%@\n%@\nОригинал сохранён в приложении. Если доступ запрещён: Настройки → Конфиденциальность → Фото → LocalSend 6."),path.lastPathComponent,error.localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];}
        }];[self updateReceiveProgress];[self refreshIdleTimer];[self refreshFiles];NSString *entry=[NSString stringWithFormat:LSL(@"Получено %lu файл(ов) от %@"),(unsigned long)[state[@"items"] count],state[@"sender"]];[self.history insertObject:entry atIndex:0];if(self.history.count>10)[self.history removeLastObject];[[NSUserDefaults standardUserDefaults] setObject:self.history forKey:@"transferHistory"];}
}
- (void)drawReceiveOverlay {
    UIView *root=self.receiveOverlay;for(UIView *v in [root.subviews copy])[v removeFromSuperview];root.backgroundColor=LSBackground(self.darkTheme);
    BOOL offer=[self.receiveState[@"phase"] isEqual:@"offer"];
    if(offer){
        UIImageView *device=[[UIImageView alloc] initWithImage:LSIcon(@"device",LSTextColor(self.darkTheme),52)];device.tag=501;[root addSubview:device];
        UILabel *name=[self label:self.receiveState[@"sender"] size:36];name.tag=502;name.textAlignment=NSTextAlignmentCenter;name.adjustsFontSizeToFitWidth=YES;name.minimumScaleFactor=.45;[root addSubview:name];
        UILabel *model=[self label:self.receiveState[@"model"] size:13];model.tag=503;model.textAlignment=NSTextAlignmentCenter;model.backgroundColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.15];model.layer.cornerRadius=6;model.clipsToBounds=YES;[root addSubview:model];
        UILabel *prompt=[self label:[NSString stringWithFormat:LSL(@"хочет отправить вам %@"),[self.receiveState[@"items"] count]==1?LSL(@"файл"):[NSString stringWithFormat:LSL(@"%lu файлов"),(unsigned long)[self.receiveState[@"items"] count]]] size:18];prompt.tag=504;prompt.textAlignment=NSTextAlignmentCenter;[root addSubview:prompt];
        UIButton *parameters=[self button:LSL(@"⚙  Параметры получения") icon:nil action:@selector(receiveParameters)];parameters.tag=505;[root addSubview:parameters];
        UIButton *reject=[self button:LSL(@"×  Отклонить") icon:nil action:@selector(rejectReceive)];reject.tag=506;reject.backgroundColor=[UIColor colorWithRed:.75 green:.09 blue:.09 alpha:1];reject.layer.cornerRadius=21;[reject setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];[root addSubview:reject];
        UIButton *accept=[self button:LSL(@"✓  Принять") icon:nil action:@selector(acceptReceive)];accept.tag=507;accept.backgroundColor=LSAccent(self.accentIndex);accept.layer.cornerRadius=21;[accept setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];[root addSubview:accept];
    }else{
        NSString *phase=self.receiveState[@"phase"];NSString *title=[phase isEqual:@"complete"]?LSL(@"Файлы получены"):([phase isEqual:@"cancelled"]||[phase isEqual:@"rejected"]?LSL(@"Получение отменено"):([phase isEqual:@"failed"]?LSL(@"Ошибка получения"):LSL(@"Получение файлов")));UILabel *heading=[self label:title size:22];heading.tag=510;[root addSubview:heading];
        UIScrollView *list=[[UIScrollView alloc] init];list.tag=511;[root addSubview:list];NSUInteger i=0;
        for(NSDictionary *file in self.receiveState[@"items"]){UIView *row=[[UIView alloc] initWithFrame:CGRectMake(0,i*64,292,60)];row.tag=600+i;row.autoresizingMask=UIViewAutoresizingFlexibleWidth;
            UIImageView *icon=[[UIImageView alloc] initWithImage:LSIcon([file[@"fileType"] hasPrefix:@"image/"]?@"media":@"file",LSTextColor(self.darkTheme),22)];icon.frame=CGRectMake(0,6,42,42);icon.contentMode=UIViewContentModeCenter;icon.backgroundColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.14];icon.layer.cornerRadius=9;icon.clipsToBounds=YES;[row addSubview:icon];
            UILabel *name=[self label:[NSString stringWithFormat:@"%@ (%@)",file[@"fileName"],[self formatBytes:[file[@"size"] longLongValue]]] size:13];name.frame=CGRectMake(52,3,235,28);name.autoresizingMask=UIViewAutoresizingFlexibleWidth;name.numberOfLines=1;name.tag=1;name.lineBreakMode=NSLineBreakByTruncatingMiddle;[row addSubview:name];
            UILabel *status=[self label:[NSString stringWithFormat:@"%@%@",LSL(self.photoResults[file[@"path"]?:@""]?:file[@"status"]),[file[@"status"] isEqual:@"Получение…"]?[NSString stringWithFormat:@" %.0f%%",[file[@"size"] doubleValue]?100*[file[@"received"] doubleValue]/[file[@"size"] doubleValue]:100]:@""] size:13];status.tag=2;status.frame=CGRectMake(52,30,235,24);status.textColor=LSAccent(self.accentIndex);[row addSubview:status];if([file[@"path"] isKindOfClass:[NSString class]]){UIButton *open=[UIButton buttonWithType:UIButtonTypeCustom];open.frame=row.bounds;open.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;open.tag=i;open.accessibilityLabel=[NSString stringWithFormat:LSL(@"Открыть %@"),file[@"fileName"]];[open addTarget:self action:@selector(openReceivedFile:) forControlEvents:UIControlEventTouchUpInside];[row addSubview:open];}[list addSubview:row];i++;}
        list.contentSize=CGSizeMake(0,i*64);
        UIView *summary=[self card];summary.tag=512;[root addSubview:summary];
        UILabel *time=[self label:LSL(@"Общее время передачи") size:18];time.tag=513;[summary addSubview:time];
        UIProgressView *progress=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];progress.tag=514;progress.progressTintColor=LSAccent(self.accentIndex);progress.trackTintColor=[LSAccent(self.accentIndex) colorWithAlphaComponent:.15];double total=[self.receiveState[@"total"] doubleValue];progress.progress=total?[self.receiveState[@"received"] doubleValue]/total:([phase isEqual:@"complete"]?1:0);[summary addSubview:progress];
        UILabel *detail=[self label:[NSString stringWithFormat:LSL(@"Файлов: %@ / %lu\nРазмер: %@ / %@"),self.receiveState[@"completed"],(unsigned long)[self.receiveState[@"items"] count],[self formatBytes:[self.receiveState[@"received"] longLongValue]],[self formatBytes:[self.receiveState[@"total"] longLongValue]]] size:13];detail.tag=515;[summary addSubview:detail];
        UIButton *details=[self button:self.receiveDetails?LSL(@"ⓘ  Скрыть"):LSL(@"ⓘ  Подробнее") icon:nil action:@selector(toggleReceiveDetails)];details.tag=516;[summary addSubview:details];
        BOOL finished=![@[@"receiving",@"offer"] containsObject:phase];UIButton *cancel=[self button:finished?LSL(@"✓  Готово"):LSL(@"×  Отменить") icon:nil action:finished?@selector(closeReceive):@selector(cancelReceive)];cancel.tag=517;[summary addSubview:cancel];
    }
    [self layoutReceiveOverlay];[self updateReceiveTime];
}
- (void)updateReceiveProgress {
    UIScrollView *list=(id)[self.receiveOverlay viewWithTag:511];NSArray *files=self.receiveState[@"items"];
    for(NSUInteger i=0;i<files.count;i++){NSDictionary *file=files[i];UILabel *status=(id)[[list viewWithTag:600+i] viewWithTag:2];status.text=[NSString stringWithFormat:@"%@%@",LSL(self.photoResults[file[@"path"]?:@""]?:file[@"status"]),[file[@"status"] isEqual:@"Получение…"]?[NSString stringWithFormat:@" %.0f%%",[file[@"size"] doubleValue]?100*[file[@"received"] doubleValue]/[file[@"size"] doubleValue]:100]:@""];}
    UIProgressView *progress=(id)[self.receiveOverlay viewWithTag:514];double total=[self.receiveState[@"total"] doubleValue];progress.progress=total?[self.receiveState[@"received"] doubleValue]/total:0;
    UILabel *detail=(id)[self.receiveOverlay viewWithTag:515];detail.text=[NSString stringWithFormat:LSL(@"Файлов: %@ / %lu\nРазмер: %@ / %@"),self.receiveState[@"completed"],(unsigned long)files.count,[self formatBytes:[self.receiveState[@"received"] longLongValue]],[self formatBytes:[self.receiveState[@"total"] longLongValue]]];[self updateReceiveTime];
}
- (void)openReceivedFile:(UIButton *)button {
    NSArray *items=self.receiveState[@"items"];if(button.tag<0 || (NSUInteger)button.tag>=items.count)return;NSString *path=items[button.tag][@"path"];if(!path.length)return;
    self.documentViewer=[UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:path]];self.documentViewer.delegate=self;
    if(![self.documentViewer presentPreviewAnimated:self.animations]) [self.documentViewer presentOptionsMenuFromRect:button.bounds inView:button animated:self.animations];
}
- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {return self.window.rootViewController;}
- (void)layoutReceiveOverlay {
    if(!self.receiveOverlay)return;CGRect bounds=self.window.rootViewController.view.bounds;CGFloat w=bounds.size.width;CGFloat top=[[[UIDevice currentDevice] systemVersion] floatValue]>=7?20:0;CGFloat h=bounds.size.height-top;self.receiveOverlay.frame=CGRectMake(0,top,w,h);
    if([self.receiveState[@"phase"] isEqual:@"offer"]){CGFloat y=MAX(70,h*.22);[self.receiveOverlay viewWithTag:501].frame=CGRectMake((w-52)/2,y,52,60);[self.receiveOverlay viewWithTag:502].frame=CGRectMake(14,y+79,w-28,51);[self.receiveOverlay viewWithTag:503].frame=CGRectMake((w-130)/2,y+143,130,25);[self.receiveOverlay viewWithTag:504].frame=CGRectMake(14,h*.62,w-28,50);[self.receiveOverlay viewWithTag:505].frame=CGRectMake(14,h*.62+57,w-28,30);CGFloat bw=(w-42)/2;[self.receiveOverlay viewWithTag:506].frame=CGRectMake(14,h-69,bw,43);[self.receiveOverlay viewWithTag:507].frame=CGRectMake(28+bw,h-69,bw,43);
    }else{[self.receiveOverlay viewWithTag:510].frame=CGRectMake(14,18,w-28,34);CGFloat cardH=self.receiveDetails?181:126;UIView *summary=[self.receiveOverlay viewWithTag:512];summary.frame=CGRectMake(12,h-cardH-21,w-24,cardH);[self.receiveOverlay viewWithTag:511].frame=CGRectMake(14,67,w-28,MAX(50,h-cardH-100));[summary viewWithTag:513].frame=CGRectMake(14,13,w-52,30);[summary viewWithTag:514].frame=CGRectMake(14,51,w-52,4);[summary viewWithTag:515].frame=CGRectMake(14,65,w-52,47);[summary viewWithTag:515].hidden=!self.receiveDetails;[summary viewWithTag:516].frame=CGRectMake(10,cardH-50,(w-44)/2,40);[summary viewWithTag:517].frame=CGRectMake((w-24)/2,cardH-50,(w-44)/2,40);}
}
- (void)updateReceiveTime {UILabel *label=(id)[self.receiveOverlay viewWithTag:513];if(!label)return;double start=[self.receiveState[@"started"] doubleValue];double end=[self.receiveState[@"ended"] doubleValue];NSInteger seconds=(NSInteger)MAX(0,(end?end:[[NSDate date] timeIntervalSince1970])-start);label.text=[NSString stringWithFormat:LSL(@"Общее время: %ld:%02ld"),(long)(seconds/60),(long)(seconds%60)];}
- (void)receiveParameters {[[[UIAlertView alloc] initWithTitle:LSL(@"Получение файлов") message:LSL(@"Файлы сохранятся в папку приложения. Изображения и совместимые видео автоматически сохраняются в Фото; HEIC преобразуется в JPEG. Остальные файлы можно выбрать кнопкой «Файл» или забрать через iTunes File Sharing. Уже существующие файлы не перезаписываются.") delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];}
- (void)acceptReceive {[self.receiver respond:YES];}
- (void)rejectReceive {[self.receiver respond:NO];}
- (void)cancelReceive {[self.receiver cancel];}
- (void)toggleReceiveDetails {self.receiveDetails=!self.receiveDetails;[self drawReceiveOverlay];}
- (void)closeReceive {[self.receiveTimer invalidate];self.receiveTimer=nil;[self.receiveOverlay removeFromSuperview];self.receiveOverlay=nil;self.receiveState=nil;[self refreshIdleTimer];self.activeTab=0;[self layoutInterface];}
- (void)applicationDidBecomeActive:(UIApplication *)application {[self updateLogoAnimation];}
- (void)applicationWillResignActive:(UIApplication *)application {[[self.receivePanel viewWithTag:10].layer removeAnimationForKey:@"slowRotation"];}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)applicationWillTerminate:(UIApplication *)application { [self.receiver stop]; self.discovering = NO; if (self.discoverySocket >= 0) { shutdown(self.discoverySocket, SHUT_RDWR); close(self.discoverySocket); self.discoverySocket = -1; } }
@end
