test core_path_regression_slice(.system: System) -> !() := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    full :: Path = Path(
        .allocator = $&allocator_storage,
        .view = c_string_as_view(.text = "/tmp/demo/file.txt"),
    )
    #defer deinit(.self = $&full, .allocator = $&allocator_storage)

    testing.expect(.condition = is_absolute(.self = &full).ok)!

    name ::= file_name(.self = &full).value
    testing.expect(.condition = name?)!
    match name {
        ..some payload {
            testing.expect(.condition = payload.value == "file.txt")!
        }
        ..none {
            testing.fail(.message = "missing file name")!
        }
    }

    ext ::= extension(.self = &full).value
    match ext {
        ..some payload {
            testing.expect(.condition = payload.value == ".txt")!
        }
        ..none {
            testing.fail(.message = "missing extension")!
        }
    }
}
