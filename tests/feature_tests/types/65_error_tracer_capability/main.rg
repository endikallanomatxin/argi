..trace_test_failure

CountingTracer : Type = (.count: UIntNative = 0)
CountingTracer implements ErrorTracer

add_context(.self: $&CountingTracer, .location: SourceLocationId, .context: StringView) -> () := {
    self&.count = self&.count + 1
}
reset_context(.self: $&CountingTracer) -> () := { self&.count = 0 }
report(.self: $&CountingTracer, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = ..ok Void()
}

fail() -> (.result: Errable#(.t: Int32, .reasons: (..trace_test_failure))) := { result = ..error(.reason = ..trace_test_failure) }
propagate() -> (.result: Errable#(.t: Int32, .reasons: (..trace_test_failure))) := {
    value := fail() !! "custom context"
    result = ..ok value
}

ok() -> !Int32 := { result = ..ok 7 }
context_text(.counter: $&UIntNative) -> (.view: StringView) := {
    counter& = counter& + 1
    view = "lazy context"
}
success(.counter: $&UIntNative) -> !Int32 := {
    value := ok() !! context_text(.counter = counter)
    result = ..ok value
}
forward#(.t: Type)(.value: Errable#(.t: t, .reasons: (..trace_test_failure))) -> (.result: Errable#(.t: t, .reasons: (..trace_test_failure))) := {
    unwrapped := value !! "original tracer"
    result = ..ok unwrapped
}
main() -> (.status_code: Int32) := {
    tracer ::= CountingTracer()
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= propagate()
    if tracer.count != 2 { status_code = 1
        return }
    counter :: UIntNative = 0
    successful ::= success(.counter = $&counter)
    if counter != 0 { status_code = 2
        return }
    if tracer.count != 2 { status_code = 3
        return }
    add_context(.context = "explicit context")
    if tracer.count != 3 { status_code = 4
        return }
    other ::= CountingTracer()
    other_virtual ::= to_virtual#(.abstract: ErrorTracer)(.value = $&other)
    assume error_tracer ::= $&other_virtual
    forwarded ::= forward#(.t: Int32)(.value = ~failed)
    if tracer.count != 4 { status_code = 5
        return }
    if other.count != 0 { status_code = 6
        return }
    reset_context(.self = $&virtual_tracer)
    if tracer.count != 0 { status_code = 7
        return }
    forwarded_again ::= forward#(.t: Int32)(.value = ~forwarded)
    if tracer.count != 1 { status_code = 8
        return }
    match forwarded_again {
        ..ok _ { status_code = 9 }
        ..error & err {
            if err&.reason == ..trace_test_failure { status_code = 0 } else { status_code = 10 }
        }
    }
}
