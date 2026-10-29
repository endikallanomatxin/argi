drops :: Int32 = 0

Owner := (.value: Int32)

Sink: Type = ()

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { drops = drops + 1 }
)

implement WriteValue#(Sink, Owner) (
    .Result      : Type = Owner
    .write_value = (.self: $&Sink, .value: Owner, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Owner
    ) {
        assume error_tracer
        result = ~value
    }
)

exercise := (.error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    sink ::= Sink()
    owner ::= Owner(42)
    returned ::= ~write(.self = $&sink, .value = ~owner)
    if returned.value != 42 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    exercise()
    if drops != 1 { status_code = 1 }
}
