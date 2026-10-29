..missing
drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

attempt := (.fail: Bool, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Owner, (..missing))
) {
    assume error_tracer

    if fail { result = ..error(.reason = ..missing) } else { result = ..ok Owner(7) }
}

work := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    assume writer ::= $&system.terminal&.stderr
    owner ::= attempt(false)!!!
    if owner.value != 7 { abort }
    attempt(true)!!!
    abort
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    work(system)
    if drops != 1 { abort }
}
