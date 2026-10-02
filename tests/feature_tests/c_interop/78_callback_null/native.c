typedef int (*Comparator)(int, int);
extern Comparator argi_callback_null(void);
static int difference(int left, int right) { return left - right; }
Comparator argi_callback_lookup(int present) { return present ? difference : 0; }
int argi_callback_accept_null(Comparator callback) { return callback == 0 && argi_callback_null() == 0; }
