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

write := (.value: $&Counter) -> () { value&.count = 42 }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    counter ::= Counter(0)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&counter)))
    {
        owner: Owner = (.release = Virtual#(Release)($&counter))
    }
    _ = unwrap_or_abort(.value = await($&future))
}
