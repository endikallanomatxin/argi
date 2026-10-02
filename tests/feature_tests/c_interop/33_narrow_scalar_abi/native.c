#include <stdbool.h>

signed char argi_c_small_signed_import(signed char value) { return value; }
unsigned char argi_c_small_unsigned_import(unsigned char value) { return value; }
short argi_c_short_import(short value) { return value; }
unsigned short argi_c_ushort_import(unsigned short value) { return value; }
bool argi_c_bool_import(bool value) { return value; }
extern signed char argi_c_small_signed(signed char value);
extern unsigned char argi_c_small_unsigned(unsigned char value);
extern short argi_c_short(short value);
extern unsigned short argi_c_ushort(unsigned short value);
extern bool argi_c_bool(bool value);
int argi_c_small_probe(void) {
    return argi_c_small_signed(-42) == -42 &&
           argi_c_small_unsigned(242) == 242 &&
           argi_c_short(-30000) == -30000 &&
           argi_c_ushort(60000) == 60000 &&
           argi_c_bool(true) && !argi_c_bool(false) ? 0 : 1;
}
