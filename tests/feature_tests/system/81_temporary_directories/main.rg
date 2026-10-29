main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    first ::= TemporaryDirectory(
        .self   = file_system
        .parent = "tests/feature_tests/system/81_temporary_directories/build"
    )!!!
    second ::= TemporaryDirectory(
        .self   = file_system
        .parent = "tests/feature_tests/system/81_temporary_directories/build"
    )!!!
    if path(.self = &first).view == path(.self = &second).view { abort }
    saved ::= string_with_capacity(.capacity = 128, .allocator = allocator)!!!
    push_view(.self = $&saved, .view = path(.self = &first).view, .allocator = allocator)!!!
    if metadata(.self = file_system, .path = path(.self = &first).view)!!!.kind != ..directory {
        abort
    }
    child_path ::= concat(
        .left = path(.self = &first).view, .right = "/child", .allocator = allocator
    )!!!
    child ::= open_file(
        .file_system = file_system
        .path        = view(.self = &child_path).view
        .allocator   = allocator
        .mode        = ..write
    )!!!
    close(.self = $&child)!!!
    match close(.self = $&first) {
        ..ok _ { abort }
        ..error _ {}
    }
    if metadata(.self = file_system, .path = path(.self = &first).view)!!!.kind != ..directory {
        abort
    }
    remove(.self = file_system, .path = view(.self = &child_path).view, .allocator = allocator)!!!
    close(.self = $&first)!!!
    close(.self = $&first)!!!
    match metadata(.self = file_system, .path = view(.self = &saved).view) {
        ..ok _ { abort } ..error error { if [error.reason != ..path_not_found] { abort } }
    }
    match TemporaryDirectory(
        .self   = file_system
        .parent = "tests/feature_tests/system/81_temporary_directories/build"
        .prefix = "../bad"
    ) {
        ..ok ~owner { abort } ..error error { if error.reason != ..invalid_path { abort } }
    }
    status_code = 0
}
