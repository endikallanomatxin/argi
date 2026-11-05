Pure(.value: CInt) -> (.result: CInt): CFunctionPointer where { no_access() }
saved :: Pure = zeroed#(Pure)()
apply_saved := (.value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
    selected ::= saved
    result = selected(.value = value, .ffi = ffi)
}
Runner#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) where { no_access() }
)
implement Runner#(Int32) (
    .run = (.self: &Int32, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
        result = apply_saved(.value = value, .ffi = ffi)
    }
)
main := () -> () {
    provider :: Int32 = 0
    runner ::= to_virtual#(Runner)(&provider)
    _ = runner
}
