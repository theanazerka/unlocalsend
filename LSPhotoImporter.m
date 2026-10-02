#import "LSLocalization.h"
#import "LSPhotoImporter.h"
#import "LSHEICDecoder.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
@interface LSPhotoImporter ()
@property (nonatomic,strong) ALAssetsLibrary *library;
@property (nonatomic,strong) NSMutableArray *queue;
@property (nonatomic,strong) NSMutableSet *scheduled;
@property (nonatomic,assign) BOOL busy;
@property (nonatomic,strong) AVAssetExportSession *videoExport;
@end
@implementation LSPhotoImporter
- (id)init {self=[super init];if(self){self.library=[[ALAssetsLibrary alloc] init];self.queue=[NSMutableArray array];self.scheduled=[NSMutableSet set];}return self;}
- (BOOL)isImporting {return self.busy || self.queue.count>0;}
+ (BOOL)isImageFile:(NSDictionary *)file {
    NSString *path=file[@"path"];if(![path isKindOfClass:[NSString class]])return NO;
    NSString *ext=path.pathExtension.lowercaseString;
    return [@[@"jpg",@"jpeg",@"png",@"heic",@"heif",@"gif",@"tif",@"tiff",@"bmp"] containsObject:ext] || ([file[@"fileType"] isKindOfClass:[NSString class]] && [file[@"fileType"] hasPrefix:@"image/"]);
}
+ (BOOL)isVideoFile:(NSDictionary *)file {
    NSString *path=file[@"path"];if(![path isKindOfClass:[NSString class]])return NO;
    return [@[@"mov",@"mp4",@"m4v",@"3gp",@"3g2",@"avi",@"mkv",@"webm",@"mts",@"m2ts"] containsObject:path.pathExtension.lowercaseString] || ([file[@"fileType"] isKindOfClass:[NSString class]] && [file[@"fileType"] hasPrefix:@"video/"]);
}
+ (BOOL)isMediaFile:(NSDictionary *)file {return [self isImageFile:file] || [self isVideoFile:file];}
- (void)enqueueFiles:(NSArray *)files completion:(void (^)(NSString *,NSError *))completion {
    for(NSDictionary *file in files){NSString *path=file[@"path"];if(![path isKindOfClass:[NSString class]]||[self.scheduled containsObject:path])continue;
        if(![LSPhotoImporter isMediaFile:file])continue;[self.scheduled addObject:path];NSMutableDictionary *job=[@{@"path":path,@"fileType":[file[@"fileType"] isKindOfClass:[NSString class]]?file[@"fileType"]:@""} mutableCopy];if(completion)job[@"completion"]=[completion copy];[self.queue addObject:job];
    }[self next];
}
- (void)finish:(NSDictionary *)job error:(NSError *)error {
    self.busy=NO;void (^completion)(NSString *,NSError *)=job[@"completion"];if(completion)completion(job[@"path"],error);[self next];
}
- (NSError *)unsupportedVideoError {
    return [NSError errorWithDomain:@"LocalSendPhoto" code:3 userInfo:@{NSLocalizedDescriptionKey:LSL(@"Видео не поддерживается этой версией iOS. Для старого iPhone отправляйте MP4/MOV с H.264. HEVC/H.265 старый iPhone не декодирует; на отправителе выберите «Наиболее совместимый» формат. Оригинал сохранён в приложении.")}];
}
- (void)saveVideoURL:(NSURL *)url temporary:(BOOL)temporary job:(NSDictionary *)job {
    dispatch_async(dispatch_get_main_queue(),^{
        [self.library writeVideoAtPathToSavedPhotosAlbum:url completionBlock:^(NSURL *assetURL,NSError *error){
            if(temporary)[[NSFileManager defaultManager] removeItemAtURL:url error:nil];
            dispatch_async(dispatch_get_main_queue(),^{self.videoExport=nil;[self finish:job error:error];});
        }];
    });
}
- (void)importVideo:(NSDictionary *)job {
    NSURL *url=[NSURL fileURLWithPath:job[@"path"]];
    if([self.library videoAtPathIsCompatibleWithSavedPhotosAlbum:url]){[self saveVideoURL:url temporary:NO job:job];return;}
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:nil];
    NSArray *compatible=[AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    // 480p keeps conversion within old devices' encoder and memory limits.
    if(![compatible containsObject:AVAssetExportPreset640x480]){dispatch_async(dispatch_get_main_queue(),^{[self finish:job error:[self unsupportedVideoError]];});return;}
    AVAssetExportSession *export=[[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPreset640x480];
    if(!export || ![export.supportedFileTypes containsObject:AVFileTypeMPEG4]){dispatch_async(dispatch_get_main_queue(),^{[self finish:job error:[self unsupportedVideoError]];});return;}
    NSURL *output=[NSURL fileURLWithPath:[[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"mp4"]];
    export.outputURL=output;export.outputFileType=AVFileTypeMPEG4;export.shouldOptimizeForNetworkUse=NO;self.videoExport=export;
    [export exportAsynchronouslyWithCompletionHandler:^{
        if(export.status==AVAssetExportSessionStatusCompleted && [self.library videoAtPathIsCompatibleWithSavedPhotosAlbum:output]){[self saveVideoURL:output temporary:YES job:job];}
        else{NSError *error=export.error?:[self unsupportedVideoError];[[NSFileManager defaultManager] removeItemAtURL:output error:nil];dispatch_async(dispatch_get_main_queue(),^{self.videoExport=nil;[self finish:job error:error];});}
    }];
}
- (void)next {
    if(self.busy || !self.queue.count)return;self.busy=YES;NSDictionary *job=self.queue[0];[self.queue removeObjectAtIndex:0];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{@autoreleasepool{
        if([LSPhotoImporter isVideoFile:job]){[self importVideo:job];return;}
        NSString *path=job[@"path"],*extension=path.pathExtension.lowercaseString;BOOL heic=[extension isEqual:@"heic"]||[extension isEqual:@"heif"]||[job[@"fileType"] isEqual:@"image/heic"]||[job[@"fileType"] isEqual:@"image/heif"];
        NSError *error=nil;NSData *data=nil;
        if(heic){
            char message[512]={0};CGImageRef image=LSDecodeHEIC(path.fileSystemRepresentation,message,sizeof(message));
            if(image){NSString *converted=[[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"jpg"];
                CGImageDestinationRef writer=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:converted],CFSTR("public.jpeg"),1,NULL);
                if(writer){CGImageDestinationAddImage(writer,image,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@.93});if(CGImageDestinationFinalize(writer))data=[NSData dataWithContentsOfFile:converted];CFRelease(writer);}CGImageRelease(image);[[NSFileManager defaultManager] removeItemAtPath:converted error:nil];
            }
            if(!data)error=[NSError errorWithDomain:@"LocalSendPhoto" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:LSL(@"Не удалось преобразовать HEIC в JPEG: %s"),message[0]?message:[LSL(@"Ошибка записи") UTF8String]]}];
        }else{
            NSURL *url=[NSURL fileURLWithPath:path];CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,NULL);
            if(source && CGImageSourceGetCount(source)>0)data=[NSData dataWithContentsOfFile:path];
            if(source)CFRelease(source);
            if(!data)error=[NSError errorWithDomain:@"LocalSendPhoto" code:2 userInfo:@{NSLocalizedDescriptionKey:LSL(@"Формат изображения не удалось открыть")}];
        }
        dispatch_async(dispatch_get_main_queue(),^{
            if(error){[self finish:job error:error];return;}
            [self.library writeImageDataToSavedPhotosAlbum:data metadata:nil completionBlock:^(NSURL *assetURL,NSError *saveError){dispatch_async(dispatch_get_main_queue(),^{[self finish:job error:saveError];});}];
        });
    }});
}
@end
