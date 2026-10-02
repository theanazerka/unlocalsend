#import <CoreGraphics/CoreGraphics.h>
// Caller owns the returned image; error is UTF-8 text, if supplied.
CGImageRef LSDecodeHEIC(const char *path, char *error, size_t errorSize);
