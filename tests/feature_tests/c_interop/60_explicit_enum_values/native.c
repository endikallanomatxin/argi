#include <limits.h>

enum Status {
    negative = -3, following_negative,
    ready = 7, following_ready,
    hexadecimal = 64, binary = 65, octal = 66,
    minimum = INT_MIN, maximum = INT_MAX
};
extern enum Status argi_enum_next(enum Status);
enum Status argi_enum_echo(enum Status value) { return value; }
int argi_enum_probe(void) {
    const enum Status values[] = {
        negative, following_negative, ready, following_ready,
        hexadecimal, binary, octal, minimum, maximum
    };
    for (unsigned i = 0; i < sizeof values / sizeof values[0]; ++i) {
        const unsigned next = (i + 1) % (sizeof values / sizeof values[0]);
        if (argi_enum_next(values[i]) != values[next]) return i + 1;
    }
    return 0;
}
