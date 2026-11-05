Pure(.value: CInt) -> (.result: CInt): CFunctionPointer where { no_access() }
Box := (.callback: Pure)
apply_slot := (.self: &Box, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
    selected ::= self&.callback
    result = selected(.value = value, .ffi = ffi)
}
Runner#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) where { no_access() }
)
implement Runner#(Box) (
    .run = (.self: &Box, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
        result = apply_slot(.self = self, .value = value, .ffi = ffi)
    }
)
main := () -> () {
    box ::= Box(.callback = zeroed#(Pure)())
    runner ::= to_virtual#(Runner)(&box)
    _ = runner
}
