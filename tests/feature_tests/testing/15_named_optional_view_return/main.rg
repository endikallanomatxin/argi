test named_optional_view_return := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := $&virtual_allocator

    path :: Path = unwrap_or_abort(
        .value = path_with_view(.allocator = allocator, .view = "/tmp/file.txt")
    )
    defer deinit(.self = $&path)

    name ::= file_name(.self = &path).value
    match name {
        ..some payload { testing.expect_with_trace(.condition = payload.value == "file.txt")! }
        ..none { testing.fail_with_trace(.message = "missing file name")! }
    }

    extension_view ::= extension(.self = &path).value
    match extension_view {
        ..some payload { testing.expect_with_trace(.condition = payload.value == ".txt")! }
        ..none { testing.fail_with_trace(.message = "missing extension")! }
    }
}
