typedef short (*Narrow)(signed char);
typedef double (*Floating)(double, float);
typedef void (*Notify)(int);
static int notified;
static short narrow(signed char value) { return (short)(value * 2); }
static double floating(double left, float right) { return left + right; }
static void notify(int value) { notified = value; }
Narrow argi_get_narrow(void) { return narrow; }
Floating argi_get_floating(void) { return floating; }
Notify argi_get_notify(void) { return notify; }
int argi_notified(void) { return notified; }

struct Values { double left; float right; double expected; };
struct Values argi_get_values(void) {
    struct Values values = {2.5, 1.25f, 3.75};
    return values;
}
