Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: &[2]&Int32)
        where { reads(self) depends_on(result, self) }
)
Provider := (.value: &[2]&Int32)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: &[2]&Int32) { result = self&.value }
)
select := (.array: &[2]&Int32, .index: UIntNative) -> (.result: Int32) {
    result = array&[index]&
}
forward_selected := (.array: &[2]&Int32, .index: UIntNative) -> (.result: Int32) {
    result = select(.array = array, .index = index)
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    original :: Int32 = 7
    storage :: [2]&Int32 = (&original, &original)
    provider ::= Provider(&storage)
    source ::= Virtual#(Source)(&provider)
    reference ::= Source#().get(&source)
    later :: Int32 = 0
    storage[1] = &later
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    element ::= forward_selected(.array = reference, .index = 1)
    if element != 9 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
