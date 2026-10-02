test named_optional_view_return(.system: System) -> !() := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    path :: Path = unwrap_or_abort(.value = Path(
        .allocator = $&allocator_storage,
        .view = c_string_as_view(.text = "/tmp/file.txt"),
    ))
    #defer deinit(.self = $&path, .allocator = $&allocator_storage)

    name ::= file_name(.self = &path).value
    match name {
        ..some payload { testing.expect(.condition = payload.value == "file.txt")! }
        ..none { testing.fail(.message = "missing file name")! }
    }

    extension_view ::= extension(.self = &path).value
    match extension_view {
        ..some payload { testing.expect(.condition = payload.value == ".txt")! }
        ..none { testing.fail(.message = "missing extension")! }
    }
}
