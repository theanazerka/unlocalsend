"""Decode real HEIC with the same C bridge used by the armv7 application."""
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parent.parent
HARNESS=r'''
#include "LSHEICDecoder.h"
#include <CoreFoundation/CoreFoundation.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
int main(int argc,char **argv){char error[512]={0};
 CGImageRef image=LSDecodeHEIC(argv[1],error,sizeof(error));
 if(!image){fprintf(stderr,"%s\n",error);return 1;}
 size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image);
 CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)argv[2],strlen(argv[2]),false);
 CGImageDestinationRef out=CGImageDestinationCreateWithURL(url,CFSTR("public.jpeg"),1,NULL);
 CGImageDestinationAddImage(out,image,NULL);bool ok=CGImageDestinationFinalize(out);
 CFRelease(out);CFRelease(url);CGImageRelease(image);
 printf("PASS: HEIC → JPEG %zu×%zu\n",width,height);return ok?0:2;
}
'''
with tempfile.TemporaryDirectory(prefix='localsend-heic-check-') as folder:
    folder=Path(folder);(folder/'main.c').write_text(HARNESS)
    subprocess.run(['clang','-O2','-I'+str(ROOT),'-I/tmp/localsend-heic-mac/include',str(ROOT/'LSHEICDecoder.c'),str(folder/'main.c'),'-L/tmp/localsend-heic-mac/lib','-lheif','-lde265','-lc++','-framework','CoreGraphics','-framework','ImageIO','-framework','CoreFoundation','-o',str(folder/'check')],check=True)
    # Reference HEVC image from libheif, plus a new HEIC produced by Apple's encoder.
    subprocess.run([str(folder/'check'),str(ROOT/'vendor/libheif-1.18.2/examples/example.heic'),str(folder/'reference.jpg')],check=True)
    subprocess.run(['sips','-s','format','heic',str(ROOT/'Resources/Icon@2x.png'),'--out',str(folder/'apple.heic')],check=True,capture_output=True)
    subprocess.run([str(folder/'check'),str(folder/'apple.heic'),str(folder/'apple.jpg')],check=True)
    for path in [folder/'reference.jpg',folder/'apple.jpg']:
        assert path.read_bytes().startswith(b'\xff\xd8')
    (folder/'broken.heic').write_bytes(b'broken file')
    assert subprocess.run([str(folder/'check'),str(folder/'broken.heic'),str(folder/'broken.jpg')],capture_output=True).returncode==1
    print('PASS: reference HEVC image, Apple HEIC, valid JPEG outputs, corrupt input rejected')
