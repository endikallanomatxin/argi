..first_failure
..second_failure
Failures : Type = (..first_failure, ..second_failure)
Probe : Type = (.count: UIntNative = 0, .sum: UIntNative = 0)
Probe implements Writer
write_byte(.self: $&Probe, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&.count = self&.count + 1
    remaining :: UInt8 = byte
    while remaining != 0 {
        self&.sum = self&.sum + 1
        remaining = remaining - 1
    }
    result = ..ok Void()
}
flush(.self: $&Probe) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := { result = ..ok Void() }
fail(.second: Bool) -> (.result: Errable#(.t: Void, .reasons: Failures)) := {
    if second { result = ..error(.reason = ..second_failure) } else { result = ..error(.reason = ..first_failure) }
}
forward(.value: Errable#(.t: Void, .reasons: Failures)) -> (.result: Errable#(.t: Void, .reasons: Failures)) := {
    value !! "after reset"
    result = ..ok Void()
}
report_value(.value: &Errable#(.t: Void, .reasons: Failures), .writer: $&Probe) -> () := {
    writer&.count = 0
    writer&.sum = 0
    match value& {
        ..ok _ { abort }
        ..error & error {
            unwrap_or_abort(.value = report_trace(.trace = &error&.trace, .stderr = writer))
        }
    }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    tracer ::= unwrap_or_abort(.value = FixedSizeErrorTracer(.allocator = system.page_allocator, .size = 288))
    virtual ::= to_virtual#(ErrorTracer)($&tracer)
    assume error_tracer ::= $&virtual
    first ::= fail(.second = false)
    second ::= fail(.second = true)
    add_context(.context = "evicted context")
    add_context(.context = "retained context")
    writer ::= Probe()
    report_value(.value = &first, .writer = $&writer)
    count ::= writer.count
    sum ::= writer.sum
    if count <= 43 { status_code = 1
        return }
    report_value(.value = &second, .writer = $&writer)
    if writer.count != count or writer.sum != sum { status_code = 2
        return }
    reset_context(.self = $&virtual)
    report_value(.value = &first, .writer = $&writer)
    if writer.count != 43 { status_code = 3
        return }
    report_value(.value = &second, .writer = $&writer)
    if writer.count != 43 { status_code = 4
        return }
    other ::= unwrap_or_abort(.value = FixedSizeErrorTracer(.allocator = system.page_allocator, .size = 288))
    other_virtual ::= to_virtual#(ErrorTracer)($&other)
    assume error_tracer ::= $&other_virtual
    propagated ::= forward(.value = ~first)
    report_value(.value = &propagated, .writer = $&writer)
    if writer.count <= 43 { status_code = 5
        return }
    count_after ::= writer.count
    sum_after ::= writer.sum
    report_value(.value = &second, .writer = $&writer)
    if writer.count != count_after or writer.sum != sum_after { status_code = 6
        return }
    -- Both old handles still observe the original tracer's shared log.
    match propagated { ..ok _ { status_code = 7 } ..error & error {
        if error&.reason != ..first_failure { status_code = 8 }
    } }
    match second { ..ok _ { status_code = 9 } ..error & error {
        if error&.reason != ..second_failure { status_code = 10 }
    } }
    writer.count = 0
    writer_virtual ::= to_virtual#(Writer)($&writer)
    unwrap_or_abort(.value = report(.self = $&other_virtual, .stderr = $&writer_virtual))
    if writer.count != 43 { status_code = 11 }
}
