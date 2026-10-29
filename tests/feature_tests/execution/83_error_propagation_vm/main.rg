..missing
..other

CountingTracer := (.count: Int32, .context_bytes: UIntNative)

implement ErrorTracer#(CountingTracer) (
    .add_context = (
        .self: $&CountingTracer, .location: SourceLocationId, .context: StringView
    ) -> () {
        metadata ::= source_location(location)
        if metadata.line == 0 or metadata.column == 0 { abort }
        self&.count = self&.count + 1
        self&.context_bytes = self&.context_bytes + byte_length(&context).count
    }
    .reset_context = (.self: $&CountingTracer) -> () {}
    .report        = (
        .self         : $&CountingTracer,
        .writer       : $&Virtual#(.contract: Writer),
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        result = ..ok Void()
    }
)

Owner := (.drops: $&Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

attempt := (
    .fail: Bool, .tracer: $&Virtual#(ErrorTracer), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..missing))) {
    assume error_tracer

    if fail {
        result = ..error(.reason = ..missing, .tracer = tracer)
    } else {
        result = ..ok 42
    }
}

propagate := (
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .drops        : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..other, ..missing))) {
    assume error_tracer

    owner ::= Owner(.drops = drops)
    value ::= attempt(fail, tracer)!
    result = ..ok value
}

create_owner := (
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .drops        : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Owner, (..missing))) {
    assume error_tracer

    if fail {
        result = ..error(.reason = ..missing, .tracer = tracer)
    } else {
        result = ..ok Owner(.drops = drops)
    }
}

forward_owner := (
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .drops        : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Owner, (..other, ..missing))) {
    assume error_tracer

    owner ::= create_owner(fail, tracer, drops)!
    result = ..ok ~owner
}

context_text := (.calls: $&Int32) -> (.result: StringView) {
    calls&= calls&+ 1
    result = "context"
}

with_context := (
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .calls        : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..other, ..missing))) {
    assume error_tracer

    value ::= attempt(fail, tracer)!! context_text(calls)
    result = ..ok value
}

exercise := () -> (.result: Int32) {
    tracer :: CountingTracer = (.count = 0, .context_bytes = 0)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    drops :: Int32 = 0
    recovered ::= propagate(true, $&erased, $&drops) handle error, value {
        match error.reason { ..missing {} ..other { abort } }
        value = 42
    }
    if recovered != 42 or drops != 1 or tracer.count != 1 { abort }
    successful ::= propagate(false, $&erased, $&drops) handle error, value { abort }
    if successful != 42 or drops != 2 or tracer.count != 1 { abort }
    context_calls :: Int32 = 0
    with_context(false, $&erased, $&context_calls) handle error { abort }
    if context_calls != 0 { abort }
    with_context(true, $&erased, $&context_calls) handle error {
        match error.reason { ..missing {} ..other { abort } }
    }
    if tracer.count != 2 or tracer.context_bytes != 7 or context_calls != 1 { abort }
    if true {
        owner ::= forward_owner(false, $&erased, $&drops) handle error, value { abort }
    }
    if drops != 3 or tracer.count != 2 { abort }
    forward_owner(true, $&erased, $&drops) handle error {
        match error.reason { ..missing {} ..other { abort } }
    }
    if drops != 3 or tracer.count != 3 { abort }
    result = 42
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    compiled ::= #run () -> (.value: Int32) { value = exercise() }
    if compiled != 42 { abort }
    #if exercise() == 42 {
        status_code = exercise()
    } else {
        abort
    }
}
