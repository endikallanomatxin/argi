Source#(.Provider: Type): Contract = (
    .get: (.self: &Provider) -> (.result: &Int32)
        where { reads(self) depends_on(result, self) }
)
Provider := (.value: &Int32)
implement Source#(Provider) (
    .get = (.self: &Provider) -> (.result: &Int32) { result = self&.value }
)
Forward#(.T: Type): Contract = (
    .forward: (.self: &T, .value: &Int32) -> (.result: &Int32)
        where { no_access() refers_to(result, value) }
)
Forwarder := (.marker: Int32)
implement Forward#(Forwarder) (
    .forward = (.self: &Forwarder, .value: &Int32) -> (.result: &Int32) { result = value }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
write := (.value: $&Int32) -> () { value& = 42 }
main := (.system: System) -> () {
    executor_provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&executor_provider)
    original :: Int32 = 7
    provider ::= Provider(&original)
    source ::= Virtual#(Source)(&provider)
    reference ::= Source#().get(&source)
    forwarder ::= Forwarder(0)
    forwarding ::= Virtual#(Forward)(&forwarder)
    later :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&later)))
    forwarded ::= Forward#().forward(&forwarding, .value = reference)
    if read(forwarded) != 7 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if later != 42 { abort }
}
