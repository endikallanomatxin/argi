struct Pair { double left, right; };
typedef struct Pair (*Transformer)(struct Pair);
struct Pair argi_cross_make(void) {
    struct Pair result = {1.5, 2.5};
    return result;
}
struct Pair argi_cross_apply(struct Pair value, Transformer callback) {
    return callback(value);
}
