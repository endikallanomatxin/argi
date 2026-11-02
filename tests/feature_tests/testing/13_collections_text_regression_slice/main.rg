test collections_text_array_slice := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    arr :: [3]Int32 = (10, 20, 30)
    testing.expect_with_trace(.condition = length(.value = arr) == 3)!
    testing.expect_with_trace(.condition = arr[0] == 10)!

    arr[1] = 99
    testing.expect_with_trace(.condition = arr[1] == 99)!
}

test collections_text_format_slice := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    text_result ::= format(.value = 7, .allocator = allocator)
    match text_result {
        ..ok ~format_payload {
            text ::= ~format_payload
            defer deinit(.self = $&text)
            view ::= view(.self = &text)
            testing.expect_with_trace(.condition = view == "7")!
        }
        ..error _ {
            testing.fail_with_trace(.message = "format failed")!
        }
    }
}
