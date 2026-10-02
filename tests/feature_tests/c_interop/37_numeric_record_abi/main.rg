Two : CStruct = (.a: CFloat, .b: CFloat)
Blend : CStruct = (.small: CFloat, .large: CDouble)
Two implements ImplicitlyCopyable
Blend implements ImplicitlyCopyable
_two(.value: Two) -> (.result: Two) : CFunction(.symbol = "argi_c_two")
_blend(.value: Blend) -> (.result: Blend) : CFunction(.symbol = "argi_c_blend")
argi_c_two_export(.value: Two) -> (.result: Two) : CFunction(.export = true) := { result = value }
argi_c_blend_export(.value: Blend) -> (.result: Blend) : CFunction(.export = true) := { result = value }
One : CStruct = (.value: CFloat)
Floats : CStruct = (.a: CFloat, .b: CFloat, .c: CFloat)
Doubles : CStruct = (.values: [4]CDouble)
Mixed : CStruct = (.number: CInt, .value: CDouble)
Reverse : CStruct = (.value: CDouble, .number: CInt)
SameWord : CStruct = (.value: CFloat, .number: CInt)
Nested : CStruct = (.one: One, .tail: [2]CFloat)
Wrapper#(.t: Type) : CStruct = (.value: t)
One implements ImplicitlyCopyable
Floats implements ImplicitlyCopyable
Doubles implements ImplicitlyCopyable
Mixed implements ImplicitlyCopyable
Reverse implements ImplicitlyCopyable
SameWord implements ImplicitlyCopyable
Nested implements ImplicitlyCopyable
Wrapper#(.t: Type) implements ImplicitlyCopyable
_one(.value: One) -> (.result: One) : CFunction(.symbol = "argi_c_one")
_floats(.value: Floats) -> (.result: Floats) : CFunction(.symbol = "argi_c_floats")
_doubles(.value: Doubles) -> (.result: Doubles) : CFunction(.symbol = "argi_c_doubles")
_mixed(.value: Mixed) -> (.result: Mixed) : CFunction(.symbol = "argi_c_mixed")
_reverse(.value: Reverse) -> (.result: Reverse) : CFunction(.symbol = "argi_c_reverse")
_same(.value: SameWord) -> (.result: SameWord) : CFunction(.symbol = "argi_c_same")
_nested(.value: Nested) -> (.result: Nested) : CFunction(.symbol = "argi_c_numeric_nested")
_wrapped(.value: Wrapper#(.t: Mixed)) -> (.result: Wrapper#(.t: Mixed)) : CFunction(.symbol = "argi_c_numeric_wrapped")
_float_crowded(.a: CFloat, .b: CFloat, .c: CFloat, .d: CFloat, .e: CFloat, .f: CFloat, .g: CFloat, .value: Floats, .last: CFloat) -> (.result: Floats) : CFunction(.symbol = "argi_c_float_crowded")
_integer_crowded(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .f: CInt, .value: Mixed, .last: CFloat) -> (.result: Mixed) : CFunction(.symbol = "argi_c_integer_crowded")
_probe() -> (.result: CInt) : CFunction(.symbol = "argi_c_numeric_probe")
argi_c_one_export(.value: One) -> (.result: One) : CFunction(.export = true) := { result = value }
argi_c_floats_export(.value: Floats) -> (.result: Floats) : CFunction(.export = true) := { result = value }
argi_c_doubles_export(.value: Doubles) -> (.result: Doubles) : CFunction(.export = true) := { result = value }
argi_c_mixed_export(.value: Mixed) -> (.result: Mixed) : CFunction(.export = true) := { result = value }
argi_c_reverse_export(.value: Reverse) -> (.result: Reverse) : CFunction(.export = true) := { result = value }
argi_c_same_export(.value: SameWord) -> (.result: SameWord) : CFunction(.export = true) := { result = value }
argi_c_numeric_nested_export(.value: Nested) -> (.result: Nested) : CFunction(.export = true) := { result = value }
argi_c_float_crowded_export(.a: CFloat, .b: CFloat, .c: CFloat, .d: CFloat, .e: CFloat, .f: CFloat, .g: CFloat, .value: Floats, .last: CFloat) -> (.result: Floats) : CFunction(.export = true) := {
    if a != 1.0 or b != 2.0 or c != 3.0 or d != 4.0 or e != 5.0 or f != 6.0 or g != 7.0 or last != 8.0 { abort }
    result = value
}
argi_c_integer_crowded_export(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .f: CInt, .value: Mixed, .last: CFloat) -> (.result: Mixed) : CFunction(.export = true) := {
    if a != 1 or b != 2 or c != 3 or d != 4 or e != 5 or f != 6 or last != 8.0 { abort }
    result = value
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    two :: Two = (.a = 2.5, .b = -3.5)
    tr := _two(two)
    if tr.a != two.a or tr.b != two.b { status_code = 12 }
    blend :: Blend = (.small = -4.5, .large = 5.5)
    br := _blend(blend)
    if br.small != blend.small or br.large != blend.large { status_code = 13 }
    one :: One = (.value = -2.5)
    if _one(one).value != -2.5 { status_code = 1 }
    floats :: Floats = (.a = 1.5, .b = -2.5, .c = 3.5)
    fr := _floats(floats)
    if fr.a != 1.5 or fr.b != -2.5 or fr.c != 3.5 { status_code = 2 }
    doubles :: Doubles = (.values = (1.5, -2.5, 3.5, 4.5))
    dr := _doubles(doubles)
    if dr.values[0] != doubles.values[0] or dr.values[1] != doubles.values[1] or dr.values[2] != doubles.values[2] or dr.values[3] != doubles.values[3] { status_code = 3 }
    mixed :: Mixed = (.number = -42, .value = 6.5)
    mr := _mixed(mixed)
    if mr.number != -42 or mr.value != mixed.value { status_code = 4 }
    reverse :: Reverse = (.value = 7.5, .number = -43)
    rr := _reverse(reverse)
    if rr.number != -43 or rr.value != reverse.value { status_code = 5 }
    same :: SameWord = (.value = 8.5, .number = -44)
    sr := _same(same)
    if sr.value != 8.5 or sr.number != -44 { status_code = 6 }
    nested :: Nested = (.one = (.value = 1.5), .tail = (-2.5, 3.5))
    nr := _nested(nested)
    if nr.one.value != 1.5 or nr.tail[0] != -2.5 or nr.tail[1] != 3.5 { status_code = 7 }
    wrapper :: Wrapper#(.t: Mixed) = (.value = mixed)
    wr := _wrapped(wrapper)
    if wr.value.number != -42 or wr.value.value != mixed.value { status_code = 8 }
    cr := _float_crowded(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, floats, 8.0)
    if cr.a != 1.5 or cr.b != -2.5 or cr.c != 3.5 { status_code = 9 }
    ir := _integer_crowded(1, 2, 3, 4, 5, 6, mixed, 8.0)
    if ir.number != -42 or ir.value != mixed.value { status_code = 10 }
    if _probe() != 0 { status_code = 11 }
}
