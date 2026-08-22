make_text(
    .allocator: $&Allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    created ::= string_with_capacity(.allocator = allocator, .capacity = 4)
    match created {
        ..ok ~ payload {
            text ::= payload
            pushed ::= push_byte(.self = $$&text, .byte = 65, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok text
                }
                ..error _ {
                    deinit(.self = $$&text, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

main(.system: System = System()) -> (.status_code: Int32) := {
    made ::= make_text(.allocator = system.allocator)
    match made {
        ..ok ~ payload {
            text ::= payload
            view ::= as_view(.self = &text)
            if view == "A" {
                deinit(.self = $$&text, .allocator = system.allocator)
                status_code = 0
            } else {
                deinit(.self = $$&text, .allocator = system.allocator)
                status_code = 1
            }
        }
        ..error _ {
            status_code = 2
        }
    }
}
