#include "thread.h"
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#endif

struct argi_thread {
    argi_thread_start start;
    void *context;
    int joined;
#ifdef _WIN32
    HANDLE handle;
#else
    pthread_t handle;
#endif
};

#ifdef _WIN32
static DWORD WINAPI argi_thread_entry(void *context) {
#else
static void *argi_thread_entry(void *context) {
#endif
    struct argi_thread *thread = context;
    thread->start(thread->context);
    return 0;
}

uintptr_t _argi_thread_create(argi_thread_start start, void *context) {
    if (!start) return 0;
    struct argi_thread *thread = malloc(sizeof(*thread));
    if (!thread) return 0;
    thread->start = start;
    thread->context = context;
    thread->joined = 0;
#ifdef _WIN32
    thread->handle = CreateThread(NULL, 0, argi_thread_entry, thread, 0, NULL);
    if (!thread->handle) { free(thread); return 0; }
#else
    if (pthread_create(&thread->handle, NULL, argi_thread_entry, thread)) {
        free(thread);
        return 0;
    }
#endif
    return (uintptr_t)thread;
}

int32_t _argi_thread_join(uintptr_t handle) {
    if (!handle) return -1;
    struct argi_thread *thread = (struct argi_thread *)handle;
    if (thread->joined) return -1;
#ifdef _WIN32
    if (WaitForSingleObject(thread->handle, INFINITE) != WAIT_OBJECT_0) return -1;
#else
    if (pthread_join(thread->handle, NULL)) return -1;
#endif
    thread->joined = 1;
    return 0;
}

int32_t _argi_thread_destroy(uintptr_t handle) {
    if (!handle) return -1;
    struct argi_thread *thread = (struct argi_thread *)handle;
    if (!thread->joined) return -1;
#ifdef _WIN32
    if (!CloseHandle(thread->handle)) return -1;
#endif
    free(thread);
    return 0;
}
