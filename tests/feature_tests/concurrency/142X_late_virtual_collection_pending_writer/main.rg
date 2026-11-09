Code#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where reads(self.state)
)
CounterProvider := (._value: &Int32)
implement Code#(CounterProvider) (
    .state = region(self._value)
    .get = (.self: &CounterProvider) -> (.result: Int32) { result = self&._value& }
)
Holder := (.code: Virtual#(Code))
code_at := (.array: &DynamicArray#(Holder), .index: UIntNative) -> (.result: Int32) {
    holder ::= unwrap_or_abort(.value = get_reference(.self = array, .index = index))
    result = Code#().get(&holder&.code)
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    allocator_provider ::= CAllocator(.ffi = system.ffi)
    assume allocator ::= Virtual#(Allocator)($&allocator_provider)
    array ::= unwrap_or_abort(.value = DynamicArray#(Holder)(.capacity = 1))
    -- The selected reference is inserted after the collection was constructed.
    value :: Int32 = 0
    counter ::= CounterProvider(._value = &value)
    push_assume_capacity(.self = $&array, .value = Holder(Virtual#(Code)(&counter)))
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    _ = code_at(&array, 0)
    _ = unwrap_or_abort(.value = await($&future))
    -- End retained references before the later counter and value leave scope.
    deinit(.self = $&array)
}
