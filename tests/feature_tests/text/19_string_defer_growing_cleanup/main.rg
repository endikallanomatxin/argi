helper := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.ok: Bool) {
    assume error_tracer
    assume allocator

    text ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = allocator, .capacity = 1)
    )
    defer deinit(.self = $&text)

    match push_ascii(.self = $&text, .byte = 65, .allocator = allocator) {
        ..ok _ {
        }
        ..error _ {
            ok = false
            return
        }
    }

    if byte_length(&text).count != 1 {
        ok = false
        return
    }

    ok = true
}

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    if helper(.allocator = $&allocator_storage).ok {
        status_code = 0
    } else {
        status_code = 1
    }
}
