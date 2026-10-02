fail() -> (.result: Errable#(.t: Void, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    fail() !! "while stepping"
    result = ..ok 0
}

main() -> (.status_code: Int32) := {
    tracer ::= ProbeTracer()
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= run()
    if tracer.count != 2 { status_code = 1
        return }
    if tracer.line != 6 { status_code = 2
        return }
    if tracer.column != 12 { status_code = 3
        return }
    if tracer.context_matches == false { status_code = 4
        return }
    match failed {
        ..ok _ { status_code = 5 }
        ..error _ { status_code = 0 }
    }
}

ProbeTracer : Type = (
    .count: UIntNative = 0
    .line: UIntNative = 0
    .column: UIntNative = 0
    .context_matches: Bool = false
)
ProbeTracer implements ErrorTracer
add_context(.self: $&ProbeTracer, .location: SourceLocationId, .context: StringView) -> () := {
    reader ::= source_location(.id = location).location
    self&.count = self&.count + 1
    self&.line = reader.line
    self&.column = reader.column
    self&.context_matches = equals(.left = context, .right = "while stepping").ok
}
reset_context(.self: $&ProbeTracer) -> () := { self&.count = 0 }
report(.self: $&ProbeTracer, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := { result = ..ok Void() }
