Counter : Abstract = (bump(.self: $&Self) -> ())
Other : Abstract = ()
Probe : Type = (.counter: $&UIntNative)
Probe implements Counter
Probe implements Other
bump(.self: $&Probe) -> () := { self&.counter& = self&.counter& + 10 }
deinit(.self: $&Probe) -> () := { self&.counter& = self&.counter& + 1 }

record#(.t: Type)(.value: t, .counter: $&UIntNative) -> () := {
    counter& = counter& + 1
}

in_generic#(.t: Type)(.value: $&t) -> () := {
    handle :: Virtual#(.abstract: Counter) = to_virtual(.value = value)
    bump(.self = $&handle)
}

run(.system: System) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume error_tracer : $&Virtual#(.abstract: ErrorTracer) = FixedSizeErrorTracer(
        .buffer = view($&zeroed#(.t: [4096]UInt8)()),
    ) | to_virtual($&_) | $&_
    add_context(.context = "inferred virtual tracer")
    reset_context(.self = error_tracer)
    result = ..ok Void()
}
-- Fallible concrete construction must still compose with inferred virtual
-- conversion, independently of the infallible fixed-buffer tracer.
FailTracer : Type = (.marker: UInt8)
FailTracer implements ErrorTracer
init(.p: $&FailTracer) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = ..error(.reason = ..out_of_memory)
}
add_context(.self: $&FailTracer, .location: SourceLocationId, .context: StringView) -> () := {}
reset_context(.self: $&FailTracer) -> () := {}
report(.self: $&FailTracer, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = ..ok Void()
}
failed_init() -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume error_tracer : $&Virtual#(.abstract: ErrorTracer) = FailTracer()! | to_virtual($&_) | $&_
    result = ..ok Void()
}
main(.system: System) -> (.status_code: Int32) := {
    positional_count :: UIntNative = 0
    record#(Int32)(.value = 7, .counter = $&positional_count)
    if positional_count != 1 { status_code = 7
        return }
    count :: UIntNative = 0
    if true {
        assume counter : $&Virtual#(.abstract: Counter) = Probe(.counter = $&count) | to_virtual($&_) | $&_
        bump(.self = counter)
        bump(.self = counter)
        if count != 20 { status_code = 2
            return }
    }
    if count != 21 { status_code = 3
        return }
    if true {
        probe ::= Probe(.counter = $&count)
        handle :: Virtual#(.abstract: Counter) = to_virtual($&probe)
        bump(.self = $&handle)
        in_generic(.value = $&probe)
        direct ::= to_virtual#(Counter)($&probe)
        bump(.self = $&direct)
        pointer ::= $&probe
        collapsed ::= pointer | $&_
        bump(.self = collapsed)
    }
    if count != 62 { status_code = 4
        return }
    failure ::= failed_init()
    match failure {
        ..ok _ { status_code = 5
            return }
        ..error & err {
            if err&.reason != ..out_of_memory { status_code = 6
                return }
        }
    }
    value ::= run(.system = system)
    match value {
        ..ok _ { status_code = 0 }
        ..error _ { status_code = 1 }
    }
}
