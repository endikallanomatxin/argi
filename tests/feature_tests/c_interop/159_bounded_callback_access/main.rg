Pure(.value: CInt) -> (.result: CInt): CFunctionPointer where { no_access() }

twice := (.value: CInt) -> (.result: CInt): CFunction { result = value * 2 }

apply := (.callback: Pure, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
    result = callback(.value = value, .ffi = ffi)
}

generic := #(.T: Type) (.value: T) -> (.result: T): CFunction { result = value }

make := () -> (.callback: Pure) { callback = Pure(.function = twice) }
Box := (.callback: Pure)
apply_slot := (.self: &Box, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
    selected ::= self&.callback
    result = selected(.value = value, .ffi = ffi)
}

Runner#(.Provider: Type): Contract = (
    .run: (.self: &Provider, .callback: Pure, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) where { no_access() }
)
implement Runner#(Int32) (
    .run = (.self: &Int32, .callback: Pure, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) { result = apply(.callback = callback, .value = value, .ffi = ffi) }
)
SlotRunner#(.Provider: Type): Contract = (
    .run_slot: (.self: &Provider, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) where { reads(self) }
)
implement SlotRunner#(Box) (
    .run_slot = (.self: &Box, .value: CInt, .ffi: $&ForeignFunctionInterface) -> (.result: CInt) {
        result = apply_slot(.self = self, .value = value, .ffi = ffi)
    }
)
main := (.system: System) -> () {
    assume ffi := system.ffi
    callback ::= make()
    specialized ::= Pure(.function = generic#(CInt))
    if specialized(.value = 42) != 42 { abort }
    callbacks: Array#(.n = 2, .t: Pure) = (callback, specialized)
    index :: UIntNative = 1
    selected ::= callbacks[index]
    if selected(.value = 21) != 21 { abort }
    box ::= Box(callback)
    if callback(.value = 21) != 42 { abort }
    if apply(.callback = box.callback, .value = 21) != 42 { abort }
    slot_runner ::= to_virtual#(SlotRunner)(&box)
    if SlotRunner#().run_slot(&slot_runner, .value = 21) != 42 { abort }
    provider :: Int32 = 0
    runner ::= to_virtual#(Runner)(&provider)
    if Runner#().run(&runner, .callback = callback, .value = 21) != 42 { abort }
}
