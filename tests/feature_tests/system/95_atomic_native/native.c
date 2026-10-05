#include "../../../../core/platforms/shared/atomic.h"
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

struct atomic_job { uintptr_t counter; unsigned iterations; };
#ifdef _WIN32
static DWORD WINAPI increment(void *context)
#else
static void *increment(void *context)
#endif
{
    struct atomic_job *job = context;
    for (unsigned i = 0; i < job->iterations; ++i)
        _argi_atomic_u32_fetch_add(job->counter, 1);
    return 0;
}

int32_t argi_atomic_probe(void) {
    uintptr_t handle = _argi_atomic_u32_create(0);
    if (!handle) return 1;
    struct atomic_job job = { handle, 25000 };
    unsigned started = 0;
    int result = 0;
#ifdef _WIN32
    HANDLE threads[4];
    for (; started < 4; ++started) {
        threads[started] = CreateThread(NULL, 0, increment, &job, 0, NULL);
        if (!threads[started]) { result = 2; break; }
    }
    for (unsigned i = 0; i < started; ++i) {
        if (WaitForSingleObject(threads[i], INFINITE) != WAIT_OBJECT_0) result = 3;
        CloseHandle(threads[i]);
    }
#else
    pthread_t threads[4];
    for (; started < 4; ++started)
        if (pthread_create(&threads[started], NULL, increment, &job)) { result = 2; break; }
    for (unsigned i = 0; i < started; ++i)
        if (pthread_join(threads[i], NULL)) result = 3;
#endif
    if (_argi_atomic_u32_load(handle) != started * job.iterations) result = 4;
    uint64_t failed = _argi_atomic_u32_compare_exchange(handle, 0, 7);
    if ((failed >> 32) || (uint32_t)failed != started * job.iterations) result = 5;
    _argi_atomic_u32_destroy(handle);
    return result;
}
