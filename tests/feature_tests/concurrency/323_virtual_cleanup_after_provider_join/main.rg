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

read_counter := (.counter: &Counter) -> (.result: Int32) { result = counter&.count }

make_owner := (.release: Virtual#(Release)) -> (.result: Owner) {
    result = (.release = release)
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    counter ::= Counter(0)
    other ::= Counter(0)
    release ::= Virtual#(Release)($&counter)
    owner ::= make_owner(release)
    first ::= unwrap_or_abort(async#(read_counter)(.args = (.counter = &counter)))
    second ::= unwrap_or_abort(async#(read_counter)(.args = (.counter = &other)))
    _ = unwrap_or_abort(await($&first))
    Deinit#(Owner).deinit($&owner)
    _ = unwrap_or_abort(await($&second))
    if counter.count != 1 { abort }
}
