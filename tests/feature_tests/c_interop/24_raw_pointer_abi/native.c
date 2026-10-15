#include <stddef.h>

static int payload = 42;
extern void *argi_pointer_export(void *pointer);

void *argi_c_static(void) { return &payload; }
int argi_c_read(void *pointer) { return pointer ? *(int *)pointer : 0; }
void *argi_c_echo(void *pointer) { return pointer; }
int argi_c_pointer_probe(void) {
    if (argi_pointer_export(&payload) != &payload) return 1;
    if (argi_pointer_export(NULL) != NULL) return 2;
    return 0;
}
