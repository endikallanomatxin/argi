make_text := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) {
    assume error_tracer

    assume allocator

    created ::= string_with_capacity(.allocator = allocator, .capacity = 4)
    match created {
        ..ok ~created_payload {
            text ::= ~created_payload
            pushed ::= push_ascii(.self = $&text, .byte = 65, .allocator = allocator)
            if is(.value = pushed, .variant = ..error) {
                deinit(.self = $&text)
                result = ..error(.reason = ..out_of_memory)
                return
            }
            result = ..ok ~text
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    made ::= make_text(.allocator = $&allocator_storage)
    match made {
        ..ok ~payload {
            text ::= ~payload
            view ::= view(.self = &text)
            if view == "A" {
                deinit(.self = $&text)
                status_code = 0
            } else {
                deinit(.self = $&text)
                status_code = 1
            }
        }
        ..error _ {
            status_code = 2
        }
    }
}
