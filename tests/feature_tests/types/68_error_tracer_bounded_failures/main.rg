..bounded_test_failure
CountAllocator : Type = (.backing: $&PageAllocator, .calls: UIntNative = 0, .fail: Bool = false)
CountAllocator implements Allocator
allocate(.self: $&CountAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.calls = self&.calls + 1
    if self&.fail { result = ..error(.reason = ..out_of_memory)
        return }
    result = allocate(.self = self&.backing, .size = size, .alignment = alignment)
}
ProbeWriter : Type = (.count: UIntNative = 0, .fail: Bool = false)
ProbeWriter implements Writer
write_byte(.self: $&ProbeWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&.count = self&.count + 1
    if self&.fail { result = ..error(.reason = ..stream_write_failed) } else { result = ..ok Void() }
}
flush(.self: $&ProbeWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := { result = ..ok Void() }
fail() -> !Void := { result = ..error(.reason = ..bounded_test_failure) }
main(.system: System) -> (.status_code: Int32) := {
    allocator :: CountAllocator = (.backing = system.page_allocator, .calls = 0, .fail = false)
    tracer ::= unwrap_or_abort(.value = FixedSizeErrorTracer(.allocator = $&allocator, .size = 288))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= fail()
    i :: UIntNative = 0
    while i < 1000 { add_context(.context = "bounded context")
        i = i + 1 }
    if allocator.calls != 1 { status_code = 1
        return }
    writer ::= ProbeWriter()
    match failed {
        ..ok _ { status_code = 2 }
        ..error & err {
            first_report ::= report_trace(.trace = &err&.trace, .stderr = $&writer)
            match first_report { ..ok _ {} ..error _ { status_code = 3
                return } }
            if writer.count == 0 or writer.count > 4096 { status_code = 4
                return }
            reset_context(.self = error_tracer)
            writer.count = 0
            empty_report ::= report_trace(.trace = &err&.trace, .stderr = $&writer)
            match empty_report { ..ok _ {} ..error _ { status_code = 5
                return } }
            if writer.count != 43 { status_code = 6
                return }
            writer.fail = true
            broken ::= report_trace(.trace = &err&.trace, .stderr = $&writer)
            match broken {
                ..ok _ { status_code = 7
                    return }
                ..error & report_error {
                    if report_error&.reason != ..stream_write_failed { status_code = 8
                        return }
                    writer.fail = false
                    writer.count = 0
                    silent ::= report_trace(.trace = &report_error&.trace, .stderr = $&writer)
                    if writer.count != 0 { status_code = 9
                        return }
                }
            }
            allocator.fail = true
            initialization ::= FixedSizeErrorTracer(.allocator = $&allocator, .size = 288)
            match initialization {
                ..ok _ { status_code = 10
                    return }
                ..error & initialization_error {
                    if initialization_error&.reason != ..out_of_memory { status_code = 11
                        return }
                    writer.count = 0
                    reported ::= report_trace(.trace = &initialization_error&.trace, .stderr = $&writer)
                    if writer.count <= 43 { status_code = 12
                        return }
                }
            }
            if allocator.calls != 2 { status_code = 13
                return }
            status_code = 0
        }
    }
}
