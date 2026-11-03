Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
callback := #(.T: Type) (.value: T) -> (.result: CInt): CFunction {
    result = 0
}
main := (.system: System) -> () {
    assume ffi := system.ffi
    value ::= Callback(.function = callback)
    _ = value
}
