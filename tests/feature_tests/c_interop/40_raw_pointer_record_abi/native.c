#include <stddef.h>
struct Buffer { unsigned char *data; size_t count; };
struct Weighted { unsigned char *data; float weight; };
struct Large { unsigned char *data; size_t count; unsigned char *other; };
struct Nested { struct Buffer buffer; int tag; };
struct Wrapper { struct Buffer value; };
static unsigned char bytes[] = {42, 43, 44};
struct Buffer argi_c_buffer_get(void) { return (struct Buffer){bytes, 3}; }
int argi_c_buffer_read(struct Buffer value) { return value.data && value.count == 3 ? value.data[0] : 0; }
struct Buffer argi_c_buffer_echo(struct Buffer value) { return value; }
struct Buffer argi_c_buffer_null(void) { return (struct Buffer){NULL, 0}; }
struct Weighted argi_c_buffer_weighted(struct Weighted value) { return value; }
struct Large argi_c_buffer_large(void) { return (struct Large){bytes, 3, bytes}; }
struct Nested argi_c_buffer_nested(void) { return (struct Nested){{bytes, 3}, -42}; }
struct Wrapper argi_c_buffer_wrapped(struct Wrapper value) { return value; }
struct Buffer argi_c_buffer_crowded(int a, int b, int c, int d, int e, struct Buffer value, int last) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || last != 6) return (struct Buffer){NULL, 0};
    return value;
}
extern struct Buffer argi_c_buffer_export(struct Buffer);
extern struct Weighted argi_c_weighted_export(struct Weighted);
extern struct Large argi_c_large_export(struct Large);
extern struct Nested argi_c_nested_export(struct Nested);
int argi_c_buffer_probe(void) {
    struct Buffer buffer = argi_c_buffer_export((struct Buffer){bytes, 3});
    if (buffer.data != bytes || buffer.count != 3) return 1;
    struct Buffer null = argi_c_buffer_export((struct Buffer){NULL, 0});
    if (null.data != NULL || null.count != 0) return 2;
    struct Weighted weighted = argi_c_weighted_export((struct Weighted){bytes, 6.5f});
    if (weighted.data != bytes || weighted.weight != 6.5f) return 3;
    struct Large large = argi_c_large_export((struct Large){bytes, 3, bytes});
    if (large.data != bytes || large.count != 3 || large.other != bytes) return 4;
    struct Nested nested = argi_c_nested_export((struct Nested){{bytes, 3}, -42});
    if (nested.buffer.data != bytes || nested.buffer.count != 3 || nested.tag != -42) return 5;
    return 0;
}
