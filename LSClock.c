#include <mach/mach_time.h>
#include "mbedtls/platform_time.h"
// clock_gettime is unavailable on iOS 6; mach_absolute_time is monotonic.
mbedtls_ms_time_t mbedtls_ms_time(void) {
    mach_timebase_info_data_t scale;
    mach_timebase_info(&scale);
    uint64_t ticks = mach_absolute_time();
    return (mbedtls_ms_time_t)((long double)ticks * scale.numer / scale.denom / 1000000.0L);
}
