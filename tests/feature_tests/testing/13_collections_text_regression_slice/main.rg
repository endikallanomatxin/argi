test collections_text_array_slice(.system: System) -> !() := {
    arr :: [3]Int32 = (10, 20, 30)
    testing.expect(.condition = length(.value = arr) == 3)!
    testing.expect(.condition = arr[0] == 10)!

    arr[1] = 99
    testing.expect(.condition = arr[1] == 99)!
}

test collections_text_format_slice(.system: System) -> !() := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text_result ::= format(.value = 7, .allocator = $&allocator_storage)
    match text_result {
        ..ok ~ format_payload {
            text ::= ~format_payload
            #defer deinit(.self = $&text, .allocator = $&allocator_storage)
            view ::= as_view(.self = &text)
            testing.expect(.condition = view == "7")!
        }
        ..error _ {
            testing.fail(.message = "format failed")!
        }
    }
}
