union Number { int integer; double real; };
union Single { float first, second; };
union Floats { float first; float values[3]; };
union Doubles { double first; double values[4]; };
union Mixed { double real; float values[3]; };
struct Nested { union Single single; float tail; };
union Wrapper { float first, second; };
#define IDENTITY(name, type) union type name(union type value) { return value; }
IDENTITY(argi_c_union_number, Number)
IDENTITY(argi_c_union_single, Single)
IDENTITY(argi_c_union_floats, Floats)
IDENTITY(argi_c_union_doubles, Doubles)
IDENTITY(argi_c_union_mixed, Mixed)
IDENTITY(argi_c_union_wrapped, Wrapper)
struct Nested argi_c_union_nested(struct Nested value) { return value; }
union Floats argi_c_union_crowded(float a, float b, float c, float d,
    float e, float f, float g, union Floats value, float last) {
    if (a != 1 || b != 2 || c != 3 || d != 4 || e != 5 || f != 6 || g != 7 || last != 8)
        return (union Floats){.values = {0, 0, 0}};
    return value;
}
extern union Number argi_c_union_number_export(union Number);
extern union Single argi_c_union_single_export(union Single);
extern union Floats argi_c_union_floats_export(union Floats);
extern union Doubles argi_c_union_doubles_export(union Doubles);
extern union Mixed argi_c_union_mixed_export(union Mixed);
extern struct Nested argi_c_union_nested_export(struct Nested);
extern union Floats argi_c_union_crowded_export(float, float, float, float,
    float, float, float, union Floats, float);
int argi_c_union_probe(void) {
    union Number integer = argi_c_union_number_export((union Number){.integer = -42});
    if (integer.integer != -42) return 1;
    union Number real = argi_c_union_number_export((union Number){.real = 6.5});
    if (real.real != 6.5) return 2;
    union Single single = argi_c_union_single_export((union Single){.second = -2.5f});
    if (single.second != -2.5f) return 3;
    union Floats floats = argi_c_union_floats_export((union Floats){.values = {1.5f, -2.5f, 3.5f}});
    if (floats.values[0] != 1.5f || floats.values[1] != -2.5f || floats.values[2] != 3.5f) return 4;
    union Doubles doubles = argi_c_union_doubles_export((union Doubles){.values = {1.5, -2.5, 3.5, 4.5}});
    if (doubles.values[0] != 1.5 || doubles.values[1] != -2.5 ||
        doubles.values[2] != 3.5 || doubles.values[3] != 4.5) return 5;
    union Mixed mixed = argi_c_union_mixed_export((union Mixed){.values = {1.5f, -2.5f, 3.5f}});
    if (mixed.values[0] != 1.5f || mixed.values[1] != -2.5f || mixed.values[2] != 3.5f) return 6;
    struct Nested nested = argi_c_union_nested_export((struct Nested){{.second = 1.5f}, -2.5f});
    if (nested.single.second != 1.5f || nested.tail != -2.5f) return 7;
    floats = argi_c_union_crowded_export(1, 2, 3, 4, 5, 6, 7, floats, 8);
    if (floats.values[0] != 1.5f || floats.values[1] != -2.5f || floats.values[2] != 3.5f) return 8;
    return 0;
}
