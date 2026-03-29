main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    allocator : $&Allocator = #reach allocator, system.allocator

    text :: String = String(.allocator = allocator, .capacity = 3)
    push_c_string(.self = $&text, .text = "ok")

    if &text == "ok" {
        return
    }

    status_code = 1
}
