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

exercise := (.system: System, .choose_first: Bool) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    counter ::= Counter(0)
    release ::= Virtual#(Release)($&counter)
    first ::= unwrap_or_abort(async#(read_counter)(.args = (.counter = &counter)))
    second ::= unwrap_or_abort(async#(read_counter)(.args = (.counter = &counter)))
    if choose_first {
        _ = unwrap_or_abort(await($&first))
    } else {
        _ = unwrap_or_abort(await($&second))
    }
    {
        owner ::= make_owner(release)
    }
    if counter.count != 1 { abort }
}

main := (.system: System) -> () {
    exercise(system, .choose_first = true)
}
