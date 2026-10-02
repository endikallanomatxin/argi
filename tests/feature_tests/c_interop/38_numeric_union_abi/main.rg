Number : CUnion = (.integer: CInt, .real: CDouble)
Single : CUnion = (.first: CFloat, .second: CFloat)
Floats : CUnion = (.first: CFloat, .values: [3]CFloat)
Doubles : CUnion = (.first: CDouble, .values: [4]CDouble)
Mixed : CUnion = (.real: CDouble, .values: [3]CFloat)
Nested : CStruct = (.single: Single, .tail: CFloat)
Wrapper#(.t: Type) : CUnion = (.first: t, .second: t)
Number implements ImplicitlyCopyable
Single implements ImplicitlyCopyable
Floats implements ImplicitlyCopyable
Doubles implements ImplicitlyCopyable
Mixed implements ImplicitlyCopyable
Nested implements ImplicitlyCopyable
Wrapper#(.t: Type) implements ImplicitlyCopyable
_number(.value: Number) -> (.result: Number) : CFunction(.symbol = "argi_c_union_number")
_single(.value: Single) -> (.result: Single) : CFunction(.symbol = "argi_c_union_single")
_floats(.value: Floats) -> (.result: Floats) : CFunction(.symbol = "argi_c_union_floats")
_doubles(.value: Doubles) -> (.result: Doubles) : CFunction(.symbol = "argi_c_union_doubles")
_mixed(.value: Mixed) -> (.result: Mixed) : CFunction(.symbol = "argi_c_union_mixed")
_nested(.value: Nested) -> (.result: Nested) : CFunction(.symbol = "argi_c_union_nested")
_wrapped(.value: Wrapper#(.t: CFloat)) -> (.result: Wrapper#(.t: CFloat)) : CFunction(.symbol = "argi_c_union_wrapped")
_crowded(.a: CFloat, .b: CFloat, .c: CFloat, .d: CFloat, .e: CFloat, .f: CFloat, .g: CFloat, .value: Floats, .last: CFloat) -> (.result: Floats) : CFunction(.symbol = "argi_c_union_crowded")
_probe() -> (.result: CInt) : CFunction(.symbol = "argi_c_union_probe")
argi_c_union_number_export(.value: Number) -> (.result: Number) : CFunction(.export = true) := { result = value }
argi_c_union_single_export(.value: Single) -> (.result: Single) : CFunction(.export = true) := { result = value }
argi_c_union_floats_export(.value: Floats) -> (.result: Floats) : CFunction(.export = true) := { result = value }
argi_c_union_doubles_export(.value: Doubles) -> (.result: Doubles) : CFunction(.export = true) := { result = value }
argi_c_union_mixed_export(.value: Mixed) -> (.result: Mixed) : CFunction(.export = true) := { result = value }
argi_c_union_nested_export(.value: Nested) -> (.result: Nested) : CFunction(.export = true) := { result = value }
argi_c_union_crowded_export(.a: CFloat, .b: CFloat, .c: CFloat, .d: CFloat, .e: CFloat, .f: CFloat, .g: CFloat, .value: Floats, .last: CFloat) -> (.result: Floats) : CFunction(.export = true) := {
    if a != 1.0 or b != 2.0 or c != 3.0 or d != 4.0 or e != 5.0 or f != 6.0 or g != 7.0 or last != 8.0 { abort }
    result = value
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    integer :: Number = (.integer = -42)
    if _number(integer).integer != -42 { status_code = 1 }
    real :: Number = (.real = 6.5)
    rr := _number(real)
    if rr.real != real.real { status_code = 2 }
    single :: Single = (.second = -2.5)
    if _single(single).second != -2.5 { status_code = 3 }
    floats :: Floats = (.values = (1.5, -2.5, 3.5))
    fr := _floats(floats)
    if fr.values[0] != 1.5 or fr.values[1] != -2.5 or fr.values[2] != 3.5 { status_code = 4 }
    doubles :: Doubles = (.values = (1.5, -2.5, 3.5, 4.5))
    dr := _doubles(doubles)
    if dr.values[0] != doubles.values[0] or dr.values[1] != doubles.values[1] or dr.values[2] != doubles.values[2] or dr.values[3] != doubles.values[3] { status_code = 5 }
    mixed :: Mixed = (.values = (1.5, -2.5, 3.5))
    mr := _mixed(mixed)
    if mr.values[0] != 1.5 or mr.values[1] != -2.5 or mr.values[2] != 3.5 { status_code = 6 }
    nested :: Nested = (.single = (.second = 1.5), .tail = -2.5)
    nr := _nested(nested)
    if nr.single.second != 1.5 or nr.tail != -2.5 { status_code = 7 }
    wrapper :: Wrapper#(.t: CFloat) = (.second = -3.5)
    if _wrapped(wrapper).second != -3.5 { status_code = 8 }
    cr := _crowded(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, floats, 8.0)
    if cr.values[0] != 1.5 or cr.values[1] != -2.5 or cr.values[2] != 3.5 { status_code = 9 }
    if _probe() != 0 { status_code = 10 }
}
