#import "LSLocalization.h"
static NSString *LSResolvedLanguage;
static NSObject *LSLanguageLock(void) {static NSObject *lock;static dispatch_once_t once;dispatch_once(&once,^{lock=[[NSObject alloc] init];});return lock;}
NSString *LSLanguagePreference(void) {return [[NSUserDefaults standardUserDefaults] stringForKey:@"appLanguage"]?:@"system";}
NSString *LSCurrentLanguage(void) {
    @synchronized(LSLanguageLock()){
        if(LSResolvedLanguage)return LSResolvedLanguage;
        NSString *preference=LSLanguagePreference();NSArray *supported=@[@"ru",@"en",@"uk"];
        if([supported containsObject:preference]){LSResolvedLanguage=preference;return LSResolvedLanguage;}
        for(NSString *language in [NSLocale preferredLanguages]){NSString *base=[[[language stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"][0] lowercaseString];if([supported containsObject:base]){LSResolvedLanguage=base;return LSResolvedLanguage;}}
        LSResolvedLanguage=@"en";return LSResolvedLanguage;
    }
}
NSString *LSL(NSString *key) {
    if(!key)return nil;
    static NSMutableDictionary *catalogs;
    @synchronized(LSLanguageLock()){
        if(!catalogs)catalogs=[NSMutableDictionary dictionary];NSString *language=LSCurrentLanguage();NSDictionary *catalog=catalogs[language];
        if(!catalog){NSString *directory=[[NSBundle mainBundle] pathForResource:language ofType:@"lproj"];catalog=[NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:@"Translations.plist"]]?:@{};catalogs[language]=catalog;}
        return catalog[key]?:key;
    }
}
void LSSetLanguage(NSString *language) {if(![@[@"system",@"ru",@"en",@"uk"] containsObject:language])return;@synchronized(LSLanguageLock()){[[NSUserDefaults standardUserDefaults] setObject:language forKey:@"appLanguage"];LSResolvedLanguage=nil;}}
