#include <stddef.h>

int argi_c_int(int value) { return value; }
long argi_c_long(long value) { return value; }
size_t argi_c_size(size_t value) { return value; }
double argi_c_double_value(void) { return 1.5; }
double argi_c_double(double value) { return value; }
extern long argi_c_scalar_export(long value);
int argi_c_scalar_probe(void) {
    return argi_c_scalar_export(-42) == -41 ? 0 : 1;
}
