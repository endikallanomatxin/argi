..missing
drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

attempt := (.fail: Bool, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(Int32, (..missing))
) {
    assume error_tracer

    if fail { result = ..error(.reason = ..missing) } else { result = ..ok 7 }
}

run := #(.WriterType: Type: Writer#(WriterType)) (
    .fail: Bool, .writer: $&WriterType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Int32 = 9) {
    assume error_tracer
    assume writer
    local ::= Owner(1)
    value ::= attempt(fail)!!!
    result = value
}

unwrap := #(.t: Type, .WriterType: Type: Writer#(WriterType)) (
    .input        : Errable#(t, (..missing)),
    .writer       : $&WriterType,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Int32 = 9) {
    assume error_tracer
    assume writer
    result = ~input!!!
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    if unwrap#(.t: Int32)(attempt(false)) != 7 { abort }
    if unwrap#(.t: Int32)(attempt(true)) != 9 { abort }
    if run(false) != 7 or drops != 1 { abort }
    if run(true) != 9 or drops != 2 { abort }
}
