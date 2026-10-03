#include <stdint.h>
#include <stdlib.h>
#include <limits.h>

typedef uint32_t DWORD;
typedef struct { int64_t QuadPart; } LARGE_INTEGER;
typedef struct { DWORD dwLowDateTime, dwHighDateTime; } FILETIME;
static int64_t frequency = 10000000;
static int64_t counter;
static uint64_t file_ticks;
static int frequency_fails, counter_fails, early_wake;
static unsigned sleep_count;
static DWORD sleep_chunks[8];
static int test_frequency(LARGE_INTEGER *value) {
    value->QuadPart = frequency;
    return !frequency_fails;
}
static int test_counter(LARGE_INTEGER *value) {
    value->QuadPart = counter;
    return !counter_fails;
}
static void test_filetime(FILETIME *value) {
    value->dwHighDateTime = (DWORD)(file_ticks >> 32);
    value->dwLowDateTime = (DWORD)file_ticks;
}
static void test_delay(DWORD milliseconds) {
    if (sleep_count == 8 || milliseconds == UINT32_MAX || !milliseconds) abort();
    sleep_chunks[sleep_count++] = milliseconds;
    uint64_t ticks = (uint64_t)milliseconds * (uint64_t)frequency / 1000;
    if (early_wake) ticks /= 2;
    counter += (int64_t)ticks;
}
#define QueryPerformanceFrequency test_frequency
#define QueryPerformanceCounter test_counter
#define GetSystemTimePreciseAsFileTime test_filetime
#define Sleep test_delay
#define _argi_clock_monotonic test_monotonic
#define _argi_clock_wall test_wall
#define _argi_clock_sleep test_sleep
#include "../../../../core/platforms/windows/time.c"

#define CHECK(condition) do { if (!(condition)) return __LINE__; } while (0)
int argi_windows_clock_probe(void) {
    uint64_t seconds;
    uint32_t ns;
    int64_t unix_seconds;
    CHECK(_argi_clock_fraction_ns(1, 3) == 333333333);
    CHECK(_argi_clock_fraction_ns(2, 3) == 666666666);
    CHECK(_argi_clock_fraction_ns(INT64_MAX - 1, INT64_MAX) == 999999999);
    CHECK(_argi_clock_fraction_ns(12345, 1000000) == 12345000);
    counter = 123456789;
    CHECK(test_monotonic(&seconds, &ns) == 0 && seconds == 12 && ns == 345678900);
    frequency = INT64_MAX;
    counter = INT64_MAX - 1;
    CHECK(test_monotonic(&seconds, &ns) == 0 && seconds == 0 && ns == 999999999);
    frequency_fails = 1;
    CHECK(test_monotonic(&seconds, &ns) == -1);
    frequency_fails = 0;
    frequency = 0;
    CHECK(test_monotonic(&seconds, &ns) == -1);
    frequency = -1;
    CHECK(test_monotonic(&seconds, &ns) == -1);
    frequency = 10000000;
    counter_fails = 1;
    CHECK(test_monotonic(&seconds, &ns) == -1);
    counter_fails = 0;
    counter = -1;
    CHECK(test_monotonic(&seconds, &ns) == -1);

    const uint64_t epoch = UINT64_C(116444736000000000);
    file_ticks = epoch;
    CHECK(test_wall(&unix_seconds, &ns) == 0 && unix_seconds == 0 && ns == 0);
    file_ticks = epoch - 1;
    CHECK(test_wall(&unix_seconds, &ns) == 0 && unix_seconds == -1 && ns == 999999900);
    file_ticks = epoch - 10000001;
    CHECK(test_wall(&unix_seconds, &ns) == 0 && unix_seconds == -2 && ns == 999999900);
    file_ticks = 0;
    CHECK(test_wall(&unix_seconds, &ns) == 0 && unix_seconds == -11644473600LL && ns == 0);
    file_ticks = epoch + 9999999;
    CHECK(test_wall(&unix_seconds, &ns) == 0 && unix_seconds == 0 && ns == 999999900);
    file_ticks = UINT64_MAX;
    CHECK(test_wall(&unix_seconds, &ns) == 0 &&
        unix_seconds == (int64_t)((UINT64_MAX - epoch) / 10000000) &&
        ns == ((UINT64_MAX - epoch) % 10000000) * 100);

    counter = 0;
    sleep_count = 0;
    CHECK(test_sleep(0, 1) == 0 && sleep_count == 1 && sleep_chunks[0] == 1);
    counter = 0;
    sleep_count = 0;
    early_wake = 1;
    CHECK(test_sleep(0, 1000000) == 0 && sleep_count == 2);
    CHECK(sleep_chunks[0] == 1 && sleep_chunks[1] == 1);
    early_wake = 0;
    counter = 0;
    frequency = 1000;
    sleep_count = 0;
    CHECK(test_sleep(4294968, 0) == 0 && sleep_count == 2);
    CHECK(sleep_chunks[0] == UINT32_MAX - 1 && sleep_chunks[1] == 706);
    CHECK(test_sleep(0, 1000000000) == -1);
    frequency_fails = 1;
    CHECK(test_sleep(0, 0) == 0 && sleep_count == 2);
    CHECK(test_sleep(0, 1) == -1);
    frequency_fails = 0;
    counter_fails = 1;
    CHECK(test_sleep(0, 1) == -1);
    return 0;
}
