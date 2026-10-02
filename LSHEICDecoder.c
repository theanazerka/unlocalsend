#include "LSHEICDecoder.h"
#include <libheif/heif.h>
#include <stdio.h>
static void LSReleaseHEICPlane(void *info, const void *data, size_t size) {
    heif_image_release((struct heif_image *)info);
}
CGImageRef LSDecodeHEIC(const char *path, char *errorText, size_t errorSize) {
    CGImageRef result=NULL;
    struct heif_context *context=heif_context_alloc();
    struct heif_image_handle *handle=NULL;
    struct heif_image *image=NULL;
    if(!context){if(errorText)snprintf(errorText,errorSize,"Not enough memory");return NULL;}
    heif_context_set_maximum_image_size_limit(context,8192);
    heif_context_set_max_decoding_threads(context,1);
    struct heif_error error=heif_context_read_from_file(context,path,NULL);
    if(error.code!=heif_error_Ok)goto done;
    error=heif_context_get_primary_image_handle(context,&handle);
    if(error.code!=heif_error_Ok)goto done;
    int width=heif_image_handle_get_width(handle),height=heif_image_handle_get_height(handle);
    if(width<=0 || height<=0 || (int64_t)width*height>24000000){
        if(errorText)snprintf(errorText,errorSize,"Image is too large for this device");goto cleanup;
    }
    struct heif_decoding_options *options=heif_decoding_options_alloc();
    if(options)options->convert_hdr_to_8bit=1;
    error=heif_decode_image(handle,&image,heif_colorspace_RGB,heif_chroma_interleaved_RGBA,options);
    heif_decoding_options_free(options);
    if(error.code!=heif_error_Ok)goto done;
    width=heif_image_get_width(image,heif_channel_interleaved);height=heif_image_get_height(image,heif_channel_interleaved);
    int stride=0;const uint8_t *pixels=heif_image_get_plane_readonly(image,heif_channel_interleaved,&stride);
    if(!pixels || stride<width*4 || height<=0)goto cleanup;
    CGDataProviderRef provider=CGDataProviderCreateWithData(image,pixels,(size_t)stride*height,LSReleaseHEICPlane);
    if(!provider)goto cleanup;
    image=NULL; // The provider owns the decoded plane until CGImage is released.
    CGColorSpaceRef colorspace=CGColorSpaceCreateDeviceRGB();
    result=CGImageCreate(width,height,8,32,stride,colorspace,kCGImageAlphaLast|kCGBitmapByteOrderDefault,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorspace);CGDataProviderRelease(provider);
    goto cleanup;
done:
    if(errorText)snprintf(errorText,errorSize,"%s",error.message?error.message:"HEIC decode failed");
cleanup:
    if(image)heif_image_release(image);
    if(handle)heif_image_handle_release(handle);
    heif_context_free(context);
    return result;
}
