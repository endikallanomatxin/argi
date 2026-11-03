#include "../../../../core/platforms/shared/thread.h"
#include "../../../../core/platforms/shared/atomic.h"
#include <stddef.h>
#include <stdlib.h>

struct gated_job { uintptr_t gate; uintptr_t entered; unsigned published; };

static void gated_worker(void *context) {
    struct gated_job *job = context;
    _argi_atomic_u32_store(job->entered, 1);
    while (!_argi_atomic_u32_load(job->gate)) {}
    job->published = 42;
}

struct thread_job { uintptr_t counter; unsigned iterations; unsigned published; };

static void increment(void *context) {
    struct thread_job *job = context;
    for (unsigned i = 0; i < job->iterations; ++i)
        _argi_atomic_u32_fetch_add(job->counter, 1);
    job->published = job->iterations;
}

int32_t argi_thread_probe(void) {
    if (_argi_thread_create(NULL, NULL)) return 1;
    if (!_argi_thread_join(0) || !_argi_thread_destroy(0)) return 2;
    uintptr_t gate = _argi_atomic_u32_create(0);
    uintptr_t entered = _argi_atomic_u32_create(0);
    if (!gate || !entered) {
        if (gate) _argi_atomic_u32_destroy(gate);
        if (entered) _argi_atomic_u32_destroy(entered);
        return 10;
    }
    struct gated_job gated = { gate, entered, 0 };
    uintptr_t blocked = _argi_thread_create(gated_worker, &gated);
    if (!blocked) {
        _argi_atomic_u32_destroy(gate);
        _argi_atomic_u32_destroy(entered);
        return 11;
    }
    while (!_argi_atomic_u32_load(entered)) {}
    int early_destroy = _argi_thread_destroy(blocked);
    _argi_atomic_u32_store(gate, 1);
    if (_argi_thread_join(blocked)) abort();
    int publication_ok = gated.published == 42;
    int destroy_result = _argi_thread_destroy(blocked);
    _argi_atomic_u32_destroy(gate);
    _argi_atomic_u32_destroy(entered);
    if (!early_destroy || !publication_ok || destroy_result) return 12;

    uintptr_t counter = _argi_atomic_u32_create(0);
    if (!counter) return 3;
    struct thread_job jobs[4] = {0};
    uintptr_t threads[4] = {0};
    unsigned started = 0;
    int result = 0;
    for (; started < 4; ++started) {
        jobs[started].counter = counter;
        jobs[started].iterations = 25000;
        threads[started] = _argi_thread_create(increment, &jobs[started]);
        if (!threads[started]) { result = 4; break; }
    }
    int joined_all = 1;
    for (unsigned i = 0; i < started; ++i) {
        if (_argi_thread_join(threads[i])) { joined_all = 0; result = 5; continue; }
        if (jobs[i].published != jobs[i].iterations) result = 6;
        if (_argi_thread_join(threads[i]) == 0) result = 7;
        if (_argi_thread_destroy(threads[i])) result = 8;
    }
    /* A failed join leaves the job's native storage live. Do not return while
       a worker might still access this stack frame or its atomic counter. */
    if (!joined_all) abort();
    if (_argi_atomic_u32_load(counter) != started * 25000) result = 9;
    _argi_atomic_u32_destroy(counter);
    return result;
}
