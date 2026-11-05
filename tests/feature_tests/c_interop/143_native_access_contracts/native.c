#include <stdint.h>
int32_t argi_access_read(const int32_t *value) { return *value; }
void argi_access_write(int32_t *value, int32_t replacement) { *value = replacement; }
int32_t argi_access_abs(int32_t value) { return value < 0 && value != INT32_MIN ? -value : value; }
typedef struct { int32_t first, second; } Pair;
void argi_access_write_first(Pair *pair, int32_t replacement) { pair->first = replacement; }
