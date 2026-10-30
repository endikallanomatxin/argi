CounterTracer := (.count: Int32 = 0)

implement ErrorTracer#(CounterTracer) (
    .add_context = (.self: $&CounterTracer, .location: SourceLocationId, .context: StringView) -> (
    ) {
        self&.count = self&.count + 1
    }
    .reset_context = (.self: $&CounterTracer) -> () { self&.count = 0 }
    .report        = (.self: $&CounterTracer, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) { result = ..ok Void() }
)

plain := (.fail: Bool) -> !Int32 {
    if fail {
        result = ..error(.reason = ..invalid_input);
        return
    }
    result = ..ok 42
}

context := (.evaluations: $&Int32) -> (.text: StringView) {
    evaluations&= evaluations&+ 1
    text = "boundary"
}

traced := (.fail: Bool, .evaluations: $&Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> !!Int32 {
    assume error_tracer
    value ::= plain(.fail = fail)!! context(.evaluations = evaluations)
    result = ..ok value
}

forward := (.evaluations: $&Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> !!Int32 {
    assume error_tracer
    value ::= traced(.fail = true, .evaluations = evaluations)!
    result = ..ok value
}

extend := (
    .original     : $&Virtual#(ErrorTracer),
    .evaluations  : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> !!Int32 {
    assume error_tracer
    value ::= forward(.evaluations = evaluations, .error_tracer = original)!! "outer boundary"
    result = ..ok value
}

direct := #(.T: Type) (.value: T, .error_tracer: $&Virtual#(ErrorTracer)) -> !!T {
    assume error_tracer
    result = ..error(.reason = ..out_of_range)
}

extend_with_local_fallback := (.original: $&Virtual#(ErrorTracer), .evaluations: $&Int32) -> !!Int32 {
    local: CounterTracer = ()
    handle ::= to_virtual#(ErrorTracer)($&local)
    assume error_tracer ::= $&handle
    value ::= forward(.evaluations = evaluations, .error_tracer = original)!! "retained original tracer"
    result = ..ok value
}

plain_widen := () -> (.result: Errable#(Int32, (..out_of_range, ..invalid_input))) {
    value ::= plain(.fail = true)!
    result = ..ok value
}

traced_widen := (.evaluations: $&Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(
        Int32,
        (..out_of_range, ..invalid_input),
        ErrorWithTrace#((..out_of_range, ..invalid_input))
    )
) {
    assume error_tracer
    value ::= traced(.fail = true, .evaluations = evaluations)!
    result = ..ok value
}

in_condition := () -> !Int32 {
    if plain(.fail = true)! == 42 { result = ..ok 42 } else { result = ..ok 0 }
}

compile_time_status ::= #run () -> (.value: Int32) {
    tracer: CounterTracer = ()
    handle ::= to_virtual#(ErrorTracer)($&tracer)
    evaluations :: Int32 = 0
    match traced(.fail = true, .evaluations = $&evaluations, .error_tracer = $&handle) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    if tracer.count != 1 or evaluations != 1 { abort }
    value = 42
}

main := () -> (.status_code: Int32 = 1) {
    if compile_time_status != 42 { abort }
    match in_condition() {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    first: CounterTracer = ()
    second: CounterTracer = ()
    first_handle ::= to_virtual#(ErrorTracer)($&first)
    second_handle ::= to_virtual#(ErrorTracer)($&second)
    evaluations :: Int32 = 0
    match traced(.fail = false, .evaluations = $&evaluations, .error_tracer = $&first_handle) {
        ..ok value { if value != 42 { abort } }
        ..error _ { abort }
    }
    if evaluations != 0 or first.count != 0 { abort }
    match extend(
        .original     = $&first_handle
        .evaluations  = $&evaluations
        .error_tracer = $&second_handle
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    if evaluations != 1 or first.count != 2 or second.count != 0 { abort }
    match direct#(.T: Int32)(.value = 42, .error_tracer = $&first_handle) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_range { abort } }
    }
    if first.count != 3 { abort }
    match extend_with_local_fallback(.original = $&first_handle, .evaluations = $&evaluations) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    if first.count != 5 or evaluations != 2 { abort }
    match plain_widen() {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    match traced_widen(.evaluations = $&evaluations, .error_tracer = $&first_handle) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_input { abort } }
    }
    if first.count != 6 or evaluations != 3 { abort }
    status_code = 0
}
