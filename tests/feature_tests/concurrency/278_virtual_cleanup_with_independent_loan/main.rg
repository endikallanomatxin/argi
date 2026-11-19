Release#(.Provider: Type): Contract = (
    .release: (.self: $&Provider) -> () where writes(self)
)

Counter := (.count: Int32)
implement Release#(Counter) (
    .release = (.self: $&Counter) -> () { self&.count = self&.count + 1 }
)

Owner := (.release: Virtual#(Release))
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        Release#().release($&self&.release)
    }
)

write := (.value: $&Int32) -> () { value& = 42 }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    counter ::= Counter(0)
    independent :: Int32 = 0
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&independent)))
    {
        owner: Owner = (.release = Virtual#(Release)($&counter))
    }
    if counter.count != 1 { abort }
    _ = unwrap_or_abort(.value = await($&future))
    if independent != 42 { abort }
}
