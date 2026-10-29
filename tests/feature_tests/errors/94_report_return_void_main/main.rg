..missing
drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

attempt := (
    .fail         : Bool,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Owner, (..missing))) {
    assume error_tracer

    if fail { result = ..error(.reason = ..missing) } else { result = ..ok Owner(7) }
}

work := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    owner ::= attempt(false)!!!
    if owner.value != 7 { abort }
    attempt(true)!!!
    abort
}

main := (.system: System) -> () {
    work(system)
    if drops != 1 { abort }
}
