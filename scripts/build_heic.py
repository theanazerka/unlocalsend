"""Rebuild bundled HEVC/HEIF decoder archives for armv7 and iOS 6."""
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parent.parent
SDK=Path.home()/'theos/sdks/iPhoneOS6.1.sdk'
PREFIX=ROOT/'vendor/heic-ios'
HEADERS=ROOT/'vendor/libcxx-3.5-headers/include'
FLAGS=f'-nostdinc++ -I{HEADERS} -stdlib=libc++ -Wno-deprecated-builtins -Wno-reserved-user-defined-literal'
COMMON=['-G','Ninja','-DCMAKE_POLICY_VERSION_MINIMUM=3.5','-DCMAKE_SYSTEM_NAME=iOS',f'-DCMAKE_OSX_SYSROOT={SDK}','-DCMAKE_OSX_ARCHITECTURES=armv7','-DCMAKE_OSX_DEPLOYMENT_TARGET=6.0',f'-DCMAKE_CXX_FLAGS={FLAGS}','-DCMAKE_BUILD_TYPE=Release',f'-DCMAKE_INSTALL_PREFIX={PREFIX}','-DBUILD_SHARED_LIBS=OFF']
with tempfile.TemporaryDirectory(prefix='localsend-heic-build-') as temporary:
    for name,extra in [('libde265-1.0.16',['-DENABLE_SDL=OFF','-DENABLE_DECODER=OFF','-DENABLE_ENCODER=OFF']),('libheif-1.18.2',[f'-DLIBDE265_INCLUDE_DIR={PREFIX}/include',f'-DLIBDE265_LIBRARY={PREFIX}/lib/libde265.a','-DENABLE_PLUGIN_LOADING=OFF','-DWITH_EXAMPLES=OFF','-DWITH_GDK_PIXBUF=OFF','-DBUILD_TESTING=OFF','-DWITH_X265=OFF','-DWITH_AOM_DECODER=OFF','-DWITH_AOM_ENCODER=OFF','-DWITH_LIBSHARPYUV=OFF','-DENABLE_MULTITHREADING_SUPPORT=OFF','-DENABLE_PARALLEL_TILE_DECODING=OFF'])]:
        build=Path(temporary)/name
        subprocess.run(['cmake','-S',str(ROOT/'vendor'/name),'-B',str(build),*COMMON,*extra],check=True)
        subprocess.run(['cmake','--build',str(build),'-j4'],check=True)
        subprocess.run(['cmake','--install',str(build)],check=True)
