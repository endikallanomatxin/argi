main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    allocator : $&Allocator = #reach allocator, system.allocator

    text :: String = String(.allocator = allocator, .capacity = 3)
    push_c_string(.self = $&text, .text = "ok")

    text_view ::= as_view(.self = &text)

    if text_view == "ok" {
        return
    }

    status_code = 1
}
