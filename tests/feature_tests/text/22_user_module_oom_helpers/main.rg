make_text := (.allocator: Virtual#(Allocator)) -> (
    .result : Errable#(.t: String, .reasons: (..out_of_memory))
) {

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
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    made ::= make_text(.allocator = allocator)
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
