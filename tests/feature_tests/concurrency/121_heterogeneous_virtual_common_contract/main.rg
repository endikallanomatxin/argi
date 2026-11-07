Code#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: Int32) where no_access()
)
First := (.marker: Int32)
Second := (.first: Int32, .second: Int32)
implement Code#(First) (
    .get = (.self: &First) -> (.result: Int32) { result = 7 }
)
implement Code#(Second) (
    .get = (.self: &Second) -> (.result: Int32) { result = 9 }
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
    first ::= First(0)
    second ::= Second(0, 0)
    array ::= unwrap_or_abort(.value = DynamicArray#(Holder)(.capacity = 2))
    push_assume_capacity(.self = $&array, .value = Holder(Virtual#(Code)(&first)))
    push_assume_capacity(.self = $&array, .value = Holder(Virtual#(Code)(&second)))
    value :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&value)))
    if code_at(&array, 0) != 7 { abort }
    if code_at(&array, 1) != 9 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if value != 42 { abort }
}
