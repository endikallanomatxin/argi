#include <stdbool.h>
#include <stdlib.h>
struct ForeignHandle { int value; };
static struct ForeignHandle *handles[16];
static int live_count, created_count, destroyed_count, violation_count;
struct ForeignHandle *argi_c_owned_create(int value, bool fail) {
    if (fail) return NULL;
    for (int i = 0; i < 16; ++i) {
        if (handles[i]) continue;
        struct ForeignHandle *handle = malloc(sizeof *handle);
        if (!handle) return NULL;
        handle->value = value;
        handles[i] = handle;
        ++live_count;
        ++created_count;
        return handle;
    }
    return NULL;
}
void argi_c_owned_destroy(struct ForeignHandle *handle) {
    for (int i = 0; i < 16; ++i) {
        if (!handle || handles[i] != handle) continue;
        handles[i] = NULL;
        --live_count;
        ++destroyed_count;
        free(handle);
        return;
    }
    ++violation_count;
}
int argi_c_owned_read(struct ForeignHandle *handle) {
    for (int i = 0; i < 16; ++i) {
        if (handle && handles[i] == handle) return handle->value;
    }
    ++violation_count;
    return -1;
}
int argi_c_owned_live(void) { return live_count; }
int argi_c_owned_created(void) { return created_count; }
int argi_c_owned_destroyed(void) { return destroyed_count; }
int argi_c_owned_violations(void) { return violation_count; }
