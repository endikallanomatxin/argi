typedef int (*Comparator)(int, int);
struct Entry { Comparator callback; int bias; };
extern Comparator argi_callback_echo(Comparator);
static int difference(int left, int right) { return left - right; }
Comparator argi_callback_lookup(void) { return argi_callback_echo(difference); }
int argi_callback_apply(Comparator callback, int left, int right) {
    return callback(left, right);
}
struct Entry argi_callback_entry(Comparator callback) {
    struct Entry entry = {callback, 17};
    return entry;
}
int argi_callback_apply_entry(struct Entry entry) {
    return entry.callback(7, 3) + entry.bias;
}
