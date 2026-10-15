// Included after the native adapter has declared the Win32 API types.
#include <stdint.h>

// Compute floor(numerator * 1e9 / denominator) without a wide product.
// QPC's positive signed frequency bounds each remainder sum below 2^64.
static uint32_t _argi_clock_fraction_ns(uint64_t numerator, uint64_t denominator) {
    uint64_t remainder = 0;
    uint32_t quotient = 0;
    for (uint32_t bit = UINT32_C(1) << 29; bit; bit >>= 1) {
        quotient *= 2;
        remainder *= 2;
        if (remainder >= denominator) {
            remainder -= denominator;
            quotient++;
        }
        if (UINT32_C(1000000000) & bit) {
            remainder += numerator;
            if (remainder >= denominator) {
                remainder -= denominator;
                quotient++;
            }
        }
    }
    return quotient;
}

int32_t _argi_clock_monotonic(uint64_t *seconds, uint32_t *nanoseconds) {
    LARGE_INTEGER frequency, counter;
    if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0 ||
        !QueryPerformanceCounter(&counter) || counter.QuadPart < 0) return -1;
    uint64_t ticks = (uint64_t)counter.QuadPart;
    uint64_t rate = (uint64_t)frequency.QuadPart;
    *seconds = ticks / rate;
    *nanoseconds = _argi_clock_fraction_ns(ticks % rate, rate);
    return 0;
}

int32_t _argi_clock_wall(int64_t *seconds, uint32_t *nanoseconds) {
    FILETIME time;
    GetSystemTimePreciseAsFileTime(&time);
    uint64_t ticks = ((uint64_t)time.dwHighDateTime << 32) | time.dwLowDateTime;
    const uint64_t epoch = UINT64_C(116444736000000000);
    const uint64_t per_second = UINT64_C(10000000);
    if (ticks >= epoch) {
        uint64_t offset = ticks - epoch;
        *seconds = (int64_t)(offset / per_second);
        *nanoseconds = (uint32_t)(offset % per_second) * 100;
    } else {
        // Negative Unix seconds retain a nonnegative fractional component.
        uint64_t offset = epoch - ticks;
        uint64_t fraction = offset % per_second;
        *seconds = -(int64_t)(offset / per_second);
        *nanoseconds = 0;
        if (fraction) {
            (*seconds)--;
            *nanoseconds = (uint32_t)(per_second - fraction) * 100;
        }
    }
    return 0;
}

int32_t _argi_clock_sleep(uint64_t seconds, uint32_t nanoseconds) {
    if (nanoseconds >= UINT32_C(1000000000)) return -1;
    if (!seconds && !nanoseconds) return 0;
    LARGE_INTEGER frequency, start, current;
    if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0 ||
        !QueryPerformanceCounter(&start) || start.QuadPart < 0) return -1;
    uint64_t rate = (uint64_t)frequency.QuadPart;
    for (;;) {
        if (!QueryPerformanceCounter(&current) || current.QuadPart < start.QuadPart) return -1;
        uint64_t elapsed = (uint64_t)current.QuadPart - (uint64_t)start.QuadPart;
        uint64_t elapsed_seconds = elapsed / rate;
        uint32_t elapsed_ns = _argi_clock_fraction_ns(elapsed % rate, rate);
        if (elapsed_seconds > seconds ||
            (elapsed_seconds == seconds && elapsed_ns >= nanoseconds)) return 0;
        uint64_t remaining_seconds = seconds - elapsed_seconds;
        uint32_t remaining_ns;
        if (elapsed_ns > nanoseconds) {
            remaining_seconds--;
            remaining_ns = UINT32_C(1000000000) - elapsed_ns + nanoseconds;
        } else {
            remaining_ns = nanoseconds - elapsed_ns;
        }
        // DWORD_MAX is INFINITE. Long delays use finite chunks, and fractional
        // milliseconds round upward. Recheck QPC even when Sleep wakes early.
        const uint64_t largest_chunk = UINT32_MAX - UINT32_C(1);
        uint64_t milliseconds = largest_chunk;
        if (remaining_seconds <= largest_chunk / 1000) {
            milliseconds = remaining_seconds * 1000 + (remaining_ns + UINT32_C(999999)) / 1000000;
            if (milliseconds > largest_chunk) milliseconds = largest_chunk;
        }
        Sleep((DWORD)milliseconds);
    }
}
