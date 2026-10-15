_int(.value: CInt) -> (.result: CInt) : CFunction(.symbol = "argi_c_int")
_long(.value: CLong) -> (.result: CLong) : CFunction(.symbol = "argi_c_long")
_size(.value: CSize) -> (.result: CSize) : CFunction(.symbol = "argi_c_size")
_double(.value: CDouble) -> (.result: CDouble) : CFunction(.symbol = "argi_c_double")
_double_value() -> (.result: CDouble) : CFunction(.symbol = "argi_c_double_value")
_probe() -> (.result: CInt) : CFunction(.symbol = "argi_c_scalar_probe")
argi_c_scalar_export(.value: CLong) -> (.result: CLong) : CFunction(.export = true) := { result = value + 1 }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    if _int(-42) != -42 { status_code = 1 }
    if _long(42) != 42 { status_code = 2 }
    if _size(42) != 42 { status_code = 3 }
    value := _double_value()
    if _double(value) != value { status_code = 4 }
    if _probe() != 0 { status_code = 5 }
}
