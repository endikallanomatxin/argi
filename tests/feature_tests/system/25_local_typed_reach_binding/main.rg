main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator : $&GeneralPurposeAllocator = $&allocator_storage

    text :: String = String(.allocator = allocator, .capacity = 3)
    push_c_string(.self = $&text, .text = "ok")

    text_view ::= as_view(.self = &text)

    if text_view == "ok" {
        return
    }

    status_code = 1
}
