#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

static int test_case;
static int sleeps;
void argi_clock_case(int value) { test_case = value; sleeps = 0; }
int argi_clock_sleeps(void) { return sleeps; }

int clock_gettime(clockid_t id, struct timespec *value) {
    if (test_case == 1) { errno = EIO; return -1; }
    if (test_case == 2 || test_case == 3) {
        value->tv_sec = INT64_C(18446744073);
        value->tv_nsec = test_case == 2 ? 709551615 : 709551616;
    } else if (test_case == 4) {
        value->tv_sec = -1;
        value->tv_nsec = 0;
    } else if (test_case == 5) {
        value->tv_sec = 0;
        value->tv_nsec = 1000000000;
    } else if (test_case == 9) {
        value->tv_sec = INT64_MIN;
        value->tv_nsec = 999999999;
    } else {
        value->tv_sec = id == CLOCK_MONOTONIC ? 1234 : -1;
        value->tv_nsec = id == CLOCK_MONOTONIC ? 567890123 : 750000000;
    }
    return 0;
}

int nanosleep(const struct timespec *request, struct timespec *remaining) {
    sleeps++;
    if (test_case == 6) { errno = EIO; return -1; }
    if (test_case == 7) {
        if (sleeps <= 213503) {
            if (request->tv_sec != 86400 || request->tv_nsec != 0) abort();
        } else {
            if (sleeps != 213504 || request->tv_sec != 84873 || request->tv_nsec != 709551615) abort();
        }
        return 0;
    }
    if (request->tv_sec != 0 || request->tv_nsec != (sleeps == 1 ? 2000000 : 1000000)) abort();
    if (sleeps == 1) {
        remaining->tv_sec = 0;
        remaining->tv_nsec = 1000000;
        errno = EINTR;
        return -1;
    }
    return 0;
}
