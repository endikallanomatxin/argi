#include <stddef.h>
struct Pointers { unsigned char *values[2]; };
struct Element { unsigned char *data; size_t count; };
struct Elements { struct Element values[2]; };
union Address { unsigned char *pointer; size_t integer; };
union Alternatives { unsigned char *pointers[2]; double numbers[2]; };
static unsigned char bytes[] = {42, 43, 44};
struct Pointers argi_c_pointers_get(void) { return (struct Pointers){{bytes, NULL}}; }
struct Elements argi_c_elements_get(void) { return (struct Elements){{{bytes, 3}, {NULL, 0}}}; }
union Address argi_c_address_get(void) { return (union Address){.pointer = bytes}; }
union Alternatives argi_c_alternatives_get(void) { return (union Alternatives){.pointers = {bytes, NULL}}; }
struct Pointers argi_c_pointers_echo(struct Pointers value) { return value; }
struct Pointers argi_c_pointers_crowded(int a, int b, int c, int d, int e, struct Pointers value, int last) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || last != 6) return (struct Pointers){{NULL, NULL}};
    return value;
}
extern struct Pointers argi_c_pointers_export(struct Pointers);
extern struct Elements argi_c_elements_export(struct Elements);
extern union Address argi_c_address_export(union Address);
extern union Alternatives argi_c_alternatives_export(union Alternatives);
int argi_c_aggregate_probe(void) {
    struct Pointers pointers = argi_c_pointers_export(argi_c_pointers_get());
    if (pointers.values[0] != bytes || pointers.values[1] != NULL) return 1;
    struct Elements elements = argi_c_elements_export(argi_c_elements_get());
    if (elements.values[0].data != bytes || elements.values[0].count != 3 || elements.values[1].data != NULL) return 2;
    union Address address = argi_c_address_export(argi_c_address_get());
    if (address.pointer != bytes) return 3;
    union Address number = argi_c_address_export((union Address){.integer = 42});
    if (number.integer != 42) return 4;
    union Alternatives alternatives = argi_c_alternatives_export(argi_c_alternatives_get());
    if (alternatives.pointers[0] != bytes || alternatives.pointers[1] != NULL) return 5;
    union Alternatives numbers = argi_c_alternatives_export((union Alternatives){.numbers = {1.5, -2.5}});
    if (numbers.numbers[0] != 1.5 || numbers.numbers[1] != -2.5) return 6;
    return 0;
}
