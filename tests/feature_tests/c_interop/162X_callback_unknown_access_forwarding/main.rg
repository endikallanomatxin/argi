Unknown(.value: CInt) -> (.result: CInt): CFunctionPointer
apply := (.callback: Unknown, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
    result = callback(.value = value, .ffi = ffi)
}
Runner#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .callback: Unknown, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) where { no_access() }
)
implement Runner#(Int32) (
    .run = (.self: &Int32, .callback: Unknown, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
        result = apply(.callback = callback, .value = value, .ffi = ffi)
    }
)
twice := (.value: CInt) -> (.result: CInt): CFunction { result = value * 2 }
main := (.system: System) -> () {
    assume ffi := system.ffi
    callback ::= Unknown(.function = twice)
    provider :: Int32 = 0
    runner ::= Virtual#(Runner)(&provider)
    _ = Runner#().run(&runner, callback, 21, ffi)
}
