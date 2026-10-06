run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    first ::= TemporaryDirectory(
        .parent = "tests/feature_tests/system/81_temporary_directories/build"
    )!
    second ::= TemporaryDirectory(
        .parent = "tests/feature_tests/system/81_temporary_directories/build"
    )!
    if path(.self = &first).view == path(.self = &second).view { abort }
    saved ::= string_with_capacity(.capacity = 128, .allocator = allocator)!
    push_view(.self = $&saved, .view = path(.self = &first).view, .allocator = allocator)!
    if metadata(.path = path(.self = &first).view)!.kind != ..directory { abort }
    close(.self = $&first)!
    close(.self = $&first)!
    match metadata(.path = as_view(.self = &saved).view) {
        ..ok _ { abort } ..error error { if [
                error.reason
                != ..path_not_found
            ] { abort } }
    }
    match TemporaryDirectory(
        .parent = "tests/feature_tests/system/81_temporary_directories/build"
        .prefix = "../bad"
    ) {
        ..ok ~owner { abort } ..error error { if error.reason != ..invalid_path { abort } }
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
