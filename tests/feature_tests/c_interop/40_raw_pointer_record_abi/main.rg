Buffer : CStruct = (.data: RawPointer#(.t: UInt8), .count: CSize)
Weighted : CStruct = (.data: RawPointer#(.t: UInt8), .weight: CFloat)
Large : CStruct = (.data: RawPointer#(.t: UInt8), .count: CSize, .other: RawPointer#(.t: UInt8))
Nested : CStruct = (.buffer: Buffer, .tag: CInt)
Wrapper#(.t: Type) : CStruct = (.value: t)
Buffer implements ImplicitlyCopyable
Weighted implements ImplicitlyCopyable
Large implements ImplicitlyCopyable
Nested implements ImplicitlyCopyable
Wrapper#(.t: Type) implements ImplicitlyCopyable
_get() -> (.result: Buffer) : CFunction(.symbol = "argi_c_buffer_get")
_read(.value: Buffer) -> (.result: CInt) : CFunction(.symbol = "argi_c_buffer_read")
_echo(.value: Buffer) -> (.result: Buffer) : CFunction(.symbol = "argi_c_buffer_echo")
_null() -> (.result: Buffer) : CFunction(.symbol = "argi_c_buffer_null")
_weighted(.value: Weighted) -> (.result: Weighted) : CFunction(.symbol = "argi_c_buffer_weighted")
_large() -> (.result: Large) : CFunction(.symbol = "argi_c_buffer_large")
_nested() -> (.result: Nested) : CFunction(.symbol = "argi_c_buffer_nested")
_wrapped(.value: Wrapper#(.t: Buffer)) -> (.result: Wrapper#(.t: Buffer)) : CFunction(.symbol = "argi_c_buffer_wrapped")
_crowded(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .value: Buffer, .last: CInt) -> (.result: Buffer) : CFunction(.symbol = "argi_c_buffer_crowded")
_probe() -> (.result: CInt) : CFunction(.symbol = "argi_c_buffer_probe")
_forward() -> (.result: Buffer) := { result = _get() }
_forward_again() -> (.result: Buffer) := { result = _forward() }
argi_c_buffer_export(.value: Buffer) -> (.result: Buffer) : CFunction(.export = true) := { result = value }
argi_c_weighted_export(.value: Weighted) -> (.result: Weighted) : CFunction(.export = true) := { result = value }
argi_c_large_export(.value: Large) -> (.result: Large) : CFunction(.export = true) := { result = value }
argi_c_nested_export(.value: Nested) -> (.result: Nested) : CFunction(.export = true) := { result = value }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    buffer := _forward_again()
    if buffer.data.address == 0 or buffer.count != 3 or _read(buffer) != 42 { status_code = 1 }
    echoed := _echo(buffer)
    if echoed.data.address != buffer.data.address or echoed.count != buffer.count { status_code = 2 }
    null := _null()
    if null.data.address != 0 or null.count != 0 { status_code = 3 }
    weighted :: Weighted = (.data = buffer.data, .weight = 6.5)
    wr := _weighted(weighted)
    if wr.data.address != buffer.data.address or wr.weight != weighted.weight { status_code = 4 }
    large := _large()
    if large.data.address != buffer.data.address or large.other.address != buffer.data.address or large.count != 3 { status_code = 5 }
    nested := _nested()
    if nested.buffer.data.address != buffer.data.address or nested.buffer.count != 3 or nested.tag != -42 { status_code = 6 }
    wrapper :: Wrapper#(.t: Buffer) = (.value = buffer)
    result := _wrapped(wrapper)
    if result.value.data.address != buffer.data.address or result.value.count != 3 { status_code = 7 }
    crowded := _crowded(1, 2, 3, 4, 5, buffer, 6)
    if crowded.data.address != buffer.data.address or crowded.count != 3 { status_code = 8 }
    if _probe() != 0 { status_code = 9 }
}
