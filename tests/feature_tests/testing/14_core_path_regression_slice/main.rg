test core_path_regression_slice := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    full :: Path = unwrap_or_abort(
        .value = path_with_view(.allocator = $&allocator_storage, .view = "/tmp/demo/file.txt")
    )
    defer deinit(.self = $&full)

    testing.expect_with_trace(.condition = is_absolute(.self = &full).ok)!

    name ::= file_name(.self = &full).value
    testing.expect_with_trace(.condition = name ?)!
    match name {
        ..some payload {
            testing.expect_with_trace(.condition = payload.value == "file.txt")!
        }
        ..none {
            testing.fail_with_trace(.message = "missing file name")!
        }
    }

    ext ::= extension(.self = &full).value
    match ext {
        ..some payload {
            testing.expect_with_trace(.condition = payload.value == ".txt")!
        }
        ..none {
            testing.fail_with_trace(.message = "missing extension")!
        }
    }
}
