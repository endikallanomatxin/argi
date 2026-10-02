_signed(.value: CSignedChar) -> (.result: CSignedChar) : CFunction(.symbol = "argi_c_small_signed_import")
_unsigned(.value: CUnsignedChar) -> (.result: CUnsignedChar) : CFunction(.symbol = "argi_c_small_unsigned_import")
_short(.value: CShort) -> (.result: CShort) : CFunction(.symbol = "argi_c_short_import")
_ushort(.value: CUShort) -> (.result: CUShort) : CFunction(.symbol = "argi_c_ushort_import")
_bool(.value: CBool) -> (.result: CBool) : CFunction(.symbol = "argi_c_bool_import")
_probe() -> (.status: CInt) : CFunction(.symbol = "argi_c_small_probe")
argi_c_small_signed(.value: CSignedChar) -> (.result: CSignedChar) : CFunction(.export = true) := { result = value }
argi_c_small_unsigned(.value: CUnsignedChar) -> (.result: CUnsignedChar) : CFunction(.export = true) := { result = value }
argi_c_short(.value: CShort) -> (.result: CShort) : CFunction(.export = true) := { result = value }
argi_c_ushort(.value: CUShort) -> (.result: CUShort) : CFunction(.export = true) := { result = value }
argi_c_bool(.value: CBool) -> (.result: CBool) : CFunction(.export = true) := { result = value }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    if _signed(-42) != -42 { status_code = 1 }
    if _unsigned(242) != 242 { status_code = 2 }
    if _short(-30000) != -30000 { status_code = 3 }
    if _ushort(60000) != 60000 { status_code = 4 }
    if _bool(true) == false { status_code = 5 }
    if _bool(false) { status_code = 6 }
    if _probe() != 0 { status_code = 7 }
}
