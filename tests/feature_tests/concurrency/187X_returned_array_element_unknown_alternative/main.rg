Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: &[2]Int32)
        where { reads(self) depends_on(result, self) }
)
Provider := (.value: &[2]Int32)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: &[2]Int32) { result = self&.value }
)
select := (.array: &[2]Int32, .index: UIntNative) -> (.result: &Int32) {
    result = &array&[index]
}
forward_selected := (.array: &[2]Int32, .index: UIntNative, .other: &Int32, .flag: Bool) -> (.result: &Int32) {
    if flag { result = select(.array = array, .index = index) } else { result = other }
}
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    storage :: [2]Int32 = (7, 9)
    provider ::= Provider(&storage)
    source ::= Virtual#(Source)(&provider)
    reference ::= Source#().get(&source)
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    element ::= forward_selected(.array = reference, .index = 1, .other = &later, .flag = false)
    if element& != 9 { abort }
    _ = unwrap_or_abort(.value = await($&future))
}
