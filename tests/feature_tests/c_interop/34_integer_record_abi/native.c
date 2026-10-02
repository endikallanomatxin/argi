struct Pair { int left, right; };
struct Words { long long first, second; };
struct Large { long long first, second, third; };
struct Nested { struct Pair pair; unsigned char bytes[3]; };
struct Wrapper { struct Pair value; };
struct Tiny { unsigned char first, second, third; };
struct Pair argi_c_pair(struct Pair value) { ++value.left; value.right += 2; return value; }
struct Words argi_c_words(struct Words value) { ++value.first; value.second += 2; return value; }
struct Large argi_c_large(struct Large value) { ++value.first; value.second += 2; value.third += 3; return value; }
struct Tiny argi_c_tiny(struct Tiny value) { return value; }
struct Words argi_c_crowded(int a, int b, int c, int d, int e, struct Words value, int f) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6) value.first = -1000;
    return argi_c_words(value);
}
struct Pair argi_c_filled(int a, int b, int c, int d, int e, int f, struct Pair value) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6) value.left = -1000;
    return argi_c_pair(value);
}
struct Large argi_c_stack(int a, int b, int c, int d, int e, int f, int g, int h, struct Large value, int i) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7 || h != 8 || i != 9) value.first = -1000;
    return argi_c_large(value);
}
extern struct Pair argi_c_pair_export(struct Pair value);
extern struct Words argi_c_words_export(struct Words value);
extern struct Large argi_c_large_export(struct Large value);
extern struct Tiny argi_c_tiny_export(struct Tiny value);
extern struct Words argi_c_crowded_export(int a, int b, int c, int d, int e, struct Words value, int f);
extern struct Large argi_c_sret_crowded_export(int a, int b, int c, int d, int e, struct Words value, int f);
int argi_c_record_probe(void) {
    struct Pair pair = argi_c_pair_export((struct Pair){-42, 30});
    struct Words words = argi_c_words_export((struct Words){100, -200});
    struct Words crowded = argi_c_crowded_export(1, 2, 3, 4, 5, (struct Words){100, -200}, 6);
    struct Large large = argi_c_large_export((struct Large){100, 200, -300});
    struct Large sret_crowded = argi_c_sret_crowded_export(1, 2, 3, 4, 5, (struct Words){100, -200}, 6);
    struct Tiny tiny = argi_c_tiny_export((struct Tiny){240, 128, 37});
    return pair.left == -41 && pair.right == 32 && words.first == 101 && words.second == -198 &&
           crowded.first == 101 && crowded.second == -198 && large.first == 101 && large.second == 202 &&
           large.third == -297 && sret_crowded.first == 101 && sret_crowded.second == -198 && sret_crowded.third == 37 && tiny.first == 240 && tiny.second == 128 && tiny.third == 37 ? 0 : 1;
}

struct Nested argi_c_nested(struct Nested value) {
    value.pair = argi_c_pair(value.pair);
    value.bytes[2] = 9;
    return value;
}
struct Wrapper argi_c_wrapped(struct Wrapper value) {
    value.value = argi_c_pair(value.value);
    return value;
}
struct Large argi_c_sret_crowded(int a, int b, int c, int d, int e, struct Words value, int f) {
    struct Words words = argi_c_crowded(a, b, c, d, e, value, f);
    return (struct Large){words.first, words.second, 37};
}
