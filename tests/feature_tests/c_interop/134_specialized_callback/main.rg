Narrow(.value: CSignedChar) -> (.result: CShort): CFunctionPointer
Packet: CStruct = (.value: CInt)
implement ImplicitlyCopyable#(Packet) ()
RecordCallback(.packet: Packet) -> (.result: Packet): CFunctionPointer
narrow_worker := #(.T: Type) (.value: T) -> (.result: CShort): CFunction {
    result = value | convert#(.to: CShort)(_)
}
record_worker := #(.T: Type) (.packet: T) -> (.result: T): CFunction { result = packet }
Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
compute := (.value: CInt) -> (.result: CInt) { result = value + 1 }
worker := #(.F: Function) (.value: CInt) -> (.result: CInt): CFunction {
    result = F(.value = value)
}
make_callback := #(.F: Function) () -> (.result: Callback) {
    result = Callback(.function = worker#(F))
}
main := (.system: System) -> (.status_code: Int32) {
    assume ffi := system.ffi
    callback ::= Callback(.function = worker#(compute))
    nested ::= make_callback#(compute)()
    if nested(.value = 41) != 42 { abort }
    narrow ::= Narrow(.function = narrow_worker#(CSignedChar))
    if narrow(.value = -7) != -7 { abort }
    record_callback ::= RecordCallback(.function = record_worker#(Packet))
    packet: Packet = (.value = 42)
    if record_callback(.packet = packet).value != 42 { abort }
    status_code = callback(.value = 41)
}
