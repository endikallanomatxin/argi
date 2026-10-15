Payload : CStruct = (
    .tag: CInt
    .value: CDouble
    .flag: CUnsignedChar
    .bytes: [3]UInt8
    .pointer: RawPointer#(.t: UInt8)
)
Pair#(.t: Type) : CStruct = (.left: t, .right: t)
_size() -> (.size: CSize) : CFunction(.symbol = "argi_c_payload_size")
_verify(.payload: &Payload) -> (.status: CInt) : CFunction(.symbol = "argi_c_payload_verify")
_fill(.payload: $&Payload) -> () : CFunction(.symbol = "argi_c_payload_fill")
_pair(.pair: &Pair#(.t: CInt)) -> (.sum: CInt) : CFunction(.symbol = "argi_c_pair_sum")
_value() -> (.value: CDouble) : CFunction(.symbol = "argi_c_payload_value")
argi_c_payload_export(.payload: &Payload) -> (.tag: CInt) : CFunction(.export = true) := { tag = payload&.tag }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    payload :: Payload = (.tag = 7, .value = _value(), .flag = 3, .bytes = (1, 2, 3), .pointer = raw_pointer#(.t: UInt8)(0))
    if size_of(.type = Payload) != _size() { status_code = 1 }
    if _verify(&payload) != 0 { status_code = 2 }
    _fill($&payload)
    if payload.tag != 42 { status_code = 3 }
    if payload.flag != 5 { status_code = 4 }
    if payload.bytes[2] != 9 { status_code = 5 }
    pair :: Pair#(.t: CInt) = (.left = 12, .right = 30)
    if _pair(&pair) != 42 { status_code = 6 }
}
