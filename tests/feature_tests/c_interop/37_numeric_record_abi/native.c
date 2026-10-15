struct Two { float a, b; };
struct Blend { float small; double large; };
struct One { float value; };
struct Floats { float a, b, c; };
struct Doubles { double values[4]; };
struct Mixed { int number; double value; };
struct Reverse { double value; int number; };
struct SameWord { float value; int number; };
struct Nested { struct One one; float tail[2]; };
struct Wrapper { struct Mixed value; };
#define IDENTITY(name, type) struct type name(struct type value) { return value; }
IDENTITY(argi_c_two, Two)
IDENTITY(argi_c_blend, Blend)
IDENTITY(argi_c_one, One)
IDENTITY(argi_c_floats, Floats)
IDENTITY(argi_c_doubles, Doubles)
IDENTITY(argi_c_mixed, Mixed)
IDENTITY(argi_c_reverse, Reverse)
IDENTITY(argi_c_same, SameWord)
IDENTITY(argi_c_numeric_nested, Nested)
IDENTITY(argi_c_numeric_wrapped, Wrapper)
struct Floats argi_c_float_crowded(float a, float b, float c, float d,
    float e, float f, float g, struct Floats value, float last) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7 || last != 8)
        return (struct Floats){0, 0, 0};
    return value;
}
struct Mixed argi_c_integer_crowded(int a, int b, int c, int d, int e,
    int f, struct Mixed value, float last) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || last != 8)
        return (struct Mixed){0, 0};
    return value;
}
extern struct Two argi_c_two_export(struct Two);
extern struct Blend argi_c_blend_export(struct Blend);
extern struct One argi_c_one_export(struct One);
extern struct Floats argi_c_floats_export(struct Floats);
extern struct Doubles argi_c_doubles_export(struct Doubles);
extern struct Mixed argi_c_mixed_export(struct Mixed);
extern struct Reverse argi_c_reverse_export(struct Reverse);
extern struct SameWord argi_c_same_export(struct SameWord);
extern struct Nested argi_c_numeric_nested_export(struct Nested);
extern struct Floats argi_c_float_crowded_export(float, float, float, float,
    float, float, float, struct Floats, float);
extern struct Mixed argi_c_integer_crowded_export(int, int, int, int, int, int,
    struct Mixed, float);
int argi_c_numeric_probe(void) {
    struct Two two = argi_c_two_export((struct Two){2.5f, -3.5f});
    if (two.a != 2.5f || two.b != -3.5f) return 10;
    struct Blend blend = argi_c_blend_export((struct Blend){-4.5f, 5.5});
    if (blend.small != -4.5f || blend.large != 5.5) return 11;
    struct One one = argi_c_one_export((struct One){-2.5f});
    if (one.value != -2.5f) return 1;
    struct Floats floats = argi_c_floats_export((struct Floats){1.5f, -2.5f, 3.5f});
    if (floats.a != 1.5f || floats.b != -2.5f || floats.c != 3.5f) return 2;
    struct Doubles doubles = argi_c_doubles_export((struct Doubles){{1.5, -2.5, 3.5, 4.5}});
    if (doubles.values[0] != 1.5 || doubles.values[1] != -2.5 ||
        doubles.values[2] != 3.5 || doubles.values[3] != 4.5) return 3;
    struct Mixed mixed = argi_c_mixed_export((struct Mixed){-42, 6.5});
    if (mixed.number != -42 || mixed.value != 6.5) return 4;
    struct Reverse reverse = argi_c_reverse_export((struct Reverse){7.5, -43});
    if (reverse.value != 7.5 || reverse.number != -43) return 5;
    struct SameWord same = argi_c_same_export((struct SameWord){8.5f, -44});
    if (same.value != 8.5f || same.number != -44) return 6;
    struct Nested nested = argi_c_numeric_nested_export((struct Nested){{1.5f}, {-2.5f, 3.5f}});
    if (nested.one.value != 1.5f || nested.tail[0] != -2.5f || nested.tail[1] != 3.5f) return 7;
    floats = argi_c_float_crowded_export(1, 2, 3, 4, 5, 6, 7, floats, 8);
    if (floats.a != 1.5f || floats.b != -2.5f || floats.c != 3.5f) return 8;
    mixed = argi_c_integer_crowded_export(1, 2, 3, 4, 5, 6, mixed, 8);
    if (mixed.number != -42 || mixed.value != 6.5) return 9;
    return 0;
}
