# HEIC for iOS 6

The app statically links libheif 1.18.2 (LGPL-3.0) and libde265 1.0.16 (LGPL-2.1).
Both complete sources and the generated armv7 archives are included in this workspace.
The corresponding licenses are also bundled in Resources/Licenses.
LLVM libc++ release_35 headers (MIT/UIUC) compile against the system iOS 6 libc++.
No libc++ runtime is bundled.

Local compatibility changes:

- libde265/libde265/CMakeLists.txt: omit the encoder subdirectory and en265.cc
  when ENABLE_ENCODER=OFF. The app only decodes HEVC.
- libcxx-3.5-headers/include/__hash_table: make the out-of-line default/move
  constructor noexcept conditions match their declarations, including the node
  allocator. Modern Clang rejects the original mismatched exception specifications.

Origins: official strukturag/libheif v1.18.2, strukturag/libde265 v1.0.16,
and llvm-mirror/libcxx release_35 archives on GitHub.

Rebuild with scripts/build_heic.py. HEIC decoding uses the primary image with its
transformations, produces 8-bit RGBA, and writes JPEG with ImageIO. Original files
remain in Documents. Images above 24 megapixels are rejected for conversion to
limit memory use on old devices; the original is still received and retained.
