main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    out_result ::= string_with_capacity(.allocator = $&allocator_storage, .capacity = 0)
    match out_result {
        ..error _ {
            status_code = 1
            return
        }
        ..ok ~ output_payload {
            out ::= ~output_payload

            step_1 ::= format_into(.out = $&out, .value = "answer=", .allocator = $&allocator_storage)
            step_2 ::= format_into(.out = $&out, .value = 42, .allocator = $&allocator_storage)
            step_3 ::= format_into(.out = $&out, .value = ", ok=", .allocator = $&allocator_storage)
            step_4 ::= format_into(.out = $&out, .value = true, .allocator = $&allocator_storage)
            if is(.value = step_1, .variant = ..ok) and is(.value = step_2, .variant = ..ok) and is(.value = step_3, .variant = ..ok) and is(.value = step_4, .variant = ..ok) {
            } else {
                deinit(.self = $&out, .allocator = $&allocator_storage)
                status_code = 7
                return
            }

            out_view ::= as_view(.self = &out)
            if out_view == "answer=42, ok=true" {
            } else {
                deinit(.self = $&out, .allocator = $&allocator_storage)
                status_code = 2
                return
            }

            deinit(.self = $&out, .allocator = $&allocator_storage)
        }
    }

    number_result ::= format(.value = -105, .allocator = $&allocator_storage)
    match number_result {
        ..error _ {
            status_code = 3
            return
        }
        ..ok ~ number_payload {
            text ::= ~number_payload
            text_view ::= as_view(.self = &text)
            if text_view == "-105" {
            } else {
                deinit(.self = $&text, .allocator = $&allocator_storage)
                status_code = 4
                return
            }
            deinit(.self = $&text, .allocator = $&allocator_storage)
        }
    }

    view ::= c_string_as_view(.text = "demo")
    view_result ::= format(.value = view, .allocator = $&allocator_storage)
    match view_result {
        ..error _ {
            status_code = 5
            return
        }
        ..ok ~ bool_payload {
            text ::= ~bool_payload
            text_view ::= as_view(.self = &text)
            if text_view == "demo" {
            } else {
                deinit(.self = $&text, .allocator = $&allocator_storage)
                status_code = 6
                return
            }
            deinit(.self = $&text, .allocator = $&allocator_storage)
        }
    }

    status_code = 0
}
