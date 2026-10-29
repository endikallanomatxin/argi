RefusingAllocator: Type = ()

implement Allocator#(RefusingAllocator) (
    .allocate = (
        .self         : $&RefusingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        assume error_tracer

        result = ..error(.reason = ..out_of_memory)
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    #if target_os("windows") {
        path: StringView = "NUL"
        c_path ::= from_literal(.data = "NUL")
    } #else {
        path: StringView = "/dev/null"
        c_path ::= from_literal(.data = "/dev/null")
    }

    -- Borrowed NUL-terminated paths require no allocation provider.
    borrowed ::= unwrap_or_abort(
        .value = open_file(.file_system = system.file_system, .path = c_path)
    )
    unwrap_or_abort(.value = close(.self = $&borrowed))
    text ::= unwrap_or_abort(
        .value = string_with_capacity(
            .allocator = allocator, .capacity = byte_length(&path).count
        )
    )
    unwrap_or_abort(.value = push_view(.self = $&text, .view = path, .allocator = allocator))
    string_file ::= unwrap_or_abort(
        .value = open_file(.file_system = system.file_system, .path = &text)
    )
    unwrap_or_abort(.value = close(.self = $&string_file))
    owned_path ::= Path(.text = ~text)
    path_file ::= unwrap_or_abort(
        .value = open_file(.file_system = system.file_system, .path = &owned_path)
    )
    unwrap_or_abort(.value = close(.self = $&path_file))

    -- StringView obtains its provider from reached Args and releases its copy.
    view_file ::= unwrap_or_abort(
        .value = open_file(.file_system = system.file_system, .path = path)
    )
    unwrap_or_abort(.value = close(.self = $&view_file))
    refusing ::= RefusingAllocator()
    match read_file(.self = system.file_system, .path = c_path, .allocator = $&refusing) {
        ..ok ~text { status_code = 3 }
        ..error error { if error.reason != ..out_of_memory { status_code = 4 } }
    }
    match open_file(.file_system = system.file_system, .path = path, .allocator = $&refusing) {
        ..ok ~file { status_code = 1 }
        ..error error { if error.reason != ..out_of_memory { status_code = 2 } }
    }
}
