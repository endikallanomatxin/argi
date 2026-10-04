python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    match python.Python(.ffi = system.ffi, .program_name = "") { ..error _ {} ..ok _ { abort } }
    initialization ::= python.initialization_error(.ffi = system.ffi).exception
    description ::= unwrap_or_abort(.value = python.exception_message(.self = &initialization,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &description).view, .pattern = "must not be empty").ok == false {
        abort
    }
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    match python.import_module(.self = &interpreter, .name = "argi_missing_module") {
        ..error _ {} ..ok _ { abort }
    }
    first ::= python.snapshot_error(.self = &interpreter).exception
    copy ::= python.clone(.self = &first).exception
    match python.import_module(.self = &interpreter, .name = "another_missing_module") {
        ..error _ {} ..ok _ { abort }
    }
    first_message ::= unwrap_or_abort(.value = python.exception_message(.self = &first,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &first_message).view, .pattern = "argi_missing_module").ok == false {
        abort
    }
    captured ::= python.capture(.self = &interpreter,
        .value = python.import_module(.self = &interpreter, .name = "third_missing_module")).result
    match captured {
        ..ok _ { abort }
        ..error ~exception {
            name ::= unwrap_or_abort(.value = python.exception_type(.self = &exception,
                    .allocator = system.page_allocator)).result
            if contains(.self = as_view(.self = &name).view, .pattern = "ModuleNotFoundError").ok == false {
                abort
            }
        }
    }
    success ::= python.capture(.self = &interpreter,
        .value = python.import_module(.self = &interpreter, .name = "json")).result
    match success { ..ok ~object {} ..error _ { abort } }
    python.deinit(.self = $&interpreter)
    preserved ::= unwrap_or_abort(.value = python.exception_message(.self = &copy,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &preserved).view, .pattern = "argi_missing_module").ok == false {
        abort
    }
}
