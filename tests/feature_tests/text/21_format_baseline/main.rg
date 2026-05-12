main(.system: System = System()) -> (.status_code: Int32) := {
    out_result ::= string_with_capacity(.allocator = system.allocator, .capacity = 0)
    match out_result {
        ..error _ {
            status_code = 1
            return
        }
        ..ok payload {
            out ::= payload

            step_1 ::= format_into(.out = $&out, .value = "answer=", .allocator = system.allocator)
            step_2 ::= format_into(.out = $&out, .value = 42, .allocator = system.allocator)
            step_3 ::= format_into(.out = $&out, .value = ", ok=", .allocator = system.allocator)
            step_4 ::= format_into(.out = $&out, .value = true, .allocator = system.allocator)
            if is(.value = step_1, .variant = ..ok) and is(.value = step_2, .variant = ..ok) and is(.value = step_3, .variant = ..ok) and is(.value = step_4, .variant = ..ok) {
            } else {
                deinit(.self = $&out, .allocator = system.allocator)
                status_code = 7
                return
            }

            out_view ::= as_view(.self = &out)
            if out_view == "answer=42, ok=true" {
            } else {
                deinit(.self = $&out, .allocator = system.allocator)
                status_code = 2
                return
            }

            deinit(.self = $&out, .allocator = system.allocator)
        }
    }

    number_result ::= format(.value = -105, .allocator = system.allocator)
    match number_result {
        ..error _ {
            status_code = 3
            return
        }
        ..ok payload {
            text ::= payload
            text_view ::= as_view(.self = &text)
            if text_view == "-105" {
            } else {
                deinit(.self = $&text, .allocator = system.allocator)
                status_code = 4
                return
            }
            deinit(.self = $&text, .allocator = system.allocator)
        }
    }

    view ::= c_string_as_view(.text = "demo")
    view_result ::= format(.value = view, .allocator = system.allocator)
    match view_result {
        ..error _ {
            status_code = 5
            return
        }
        ..ok payload {
            text ::= payload
            text_view ::= as_view(.self = &text)
            if text_view == "demo" {
            } else {
                deinit(.self = $&text, .allocator = system.allocator)
                status_code = 6
                return
            }
            deinit(.self = $&text, .allocator = system.allocator)
        }
    }

    status_code = 0
}
