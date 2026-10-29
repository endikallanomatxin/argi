const std = @import("std");
const support = @import("frontend_test_support.zig");

test "borrowed array extracted from imported Errable retains lexical lifetime" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{ .name = "imported_errable_array_scope", .files = &.{
        .{ .path = "main.rg", .code =
        \\dep := import("./dep")
        \\main := () -> () {
        \\    assume error_tracer ::= $&noop_error_tracer
        \\    escaped :: ArrayView#(Int32)
        \\    {
        \\        values: [2]Int32 = (1, 2)
        \\        wrapped ::= dep.borrow(.value = &values)
        \\        match wrapped { ..ok value { escaped = value } ..error _ { abort } }
        \\    }
        \\    value ::= get(&escaped, .index = 0)
        \\}
        },
        .{ .path = "dep/main.rg", .code =
        \\borrow := (.value: &[2]Int32) -> (.result: Errable#(ArrayView#(Int32), (..invalid_input))) {
        \\    result = ..ok view(value)
        \\}
        },
    }, .diagnostic = .{ .message = "depends on a root that has ended" } });
    inline for (.{ false, true }) |use_unwrap| {
        _ = try environment.check(.{ .name = if (use_unwrap) "imported_errable_array_unwrap" else "imported_errable_array_reference", .files = &.{
            .{ .path = "main.rg", .code =
            \\dep := import("./dep")
            \\main := () -> () {
            \\    assume error_tracer ::= $&noop_error_tracer
            \\    escaped :: &[2]Int32
            \\    {
            \\        values: [2]Int32 = (1, 2)
            \\        wrapped ::= dep.borrow(.value = &values)
            \\
            ++ (if (use_unwrap)
                \\        escaped = unwrap_or_abort(.value = wrapped)
            else
                \\        match wrapped { ..ok value { escaped = value } ..error _ { abort } }
            ) ++
                \\
                \\    }
                \\    value ::= escaped&[0]
                \\}
            },
            .{ .path = "dep/main.rg", .code =
            \\borrow := (.value: &[2]Int32) -> (.result: Errable#(&[2]Int32, (..invalid_input))) {
            \\    result = ..ok value
            \\}
            },
        }, .diagnostic = .{ .message = "depends on a root that has ended" } });
    }
    _ = try environment.check(.{ .name = "imported_errable_live_array", .files = &.{
        .{ .path = "main.rg", .code =
        \\dep := import("./dep")
        \\main := () -> () {
        \\    assume error_tracer ::= $&noop_error_tracer
        \\    values: [2]Int32 = (1, 2)
        \\    escaped :: ArrayView#(Int32)
        \\    {
        \\        wrapped ::= dep.borrow(.value = &values)
        \\        match wrapped { ..ok value { escaped = value } ..error _ { abort } }
        \\    }
        \\    value ::= get(&escaped, .index = 0)
        \\}
        },
        .{ .path = "dep/main.rg", .code =
        \\borrow := (.value: &[2]Int32) -> (.result: Errable#(ArrayView#(Int32), (..invalid_input))) {
        \\    result = ..ok view(value)
        \\}
        },
    } });
}

test "real core environment reuses modules without sharing rejected semantic state" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    const good = support.Case{
        .name = "module_isolation",
        .files = &.{
            .{ .path = "main.rg", .code = "dep := import(\"./dep\")\nmain := () -> (.status_code: Int32) { status_code = dep.answer().result }" },
            .{ .path = "dep/value.rg", .code = "answer := () -> (.result: Int32) { result = 42 }" },
        },
    };
    const cold = try environment.check(good);
    try std.testing.expect(cold.cache_misses > 0);
    var rejected = good;
    rejected.files = &.{
        .{ .path = "main.rg", .code = "dep := import(\"./dep\")\nmain := () -> (.status_code: Int32) { missing = dep.answer().result }" },
        good.files[1],
    };
    rejected.diagnostic = .{ .message = "cannot assign to undeclared binding 'missing'", .file = "main.rg", .marker = "missing =" };
    const failed = try environment.check(rejected);
    try std.testing.expect(failed.cache_hits > 0);
    const restored = try environment.check(good);
    try std.testing.expect(restored.cache_hits > 0);
}

test "real core environment preserves private library storage and allocator safety" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "denied_copy_before_pending_call",
        .files = &.{.{ .path = "main.rg", .code =
        \\Owner := (.value: Int32)
        \\implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})
        \\main := () -> () {
        \\    assume error_tracer ::= $&noop_error_tracer
        \\    owner: Owner = (.value = 1)
        \\    copy ::= owner
        \\    missing(copy)
        \\}
        }},
        .diagnostic = .{ .message = "type 'Owner' cannot be copied implicitly; use '~value' to transfer ownership", .file = "main.rg", .marker = "owner\n", .exact = true },
    });
    _ = try environment.checkModule(std.testing.allocator, "tests/feature_tests/text/70X_string_private_storage", .{ .message = "field '_length' is private", .file = "main.rg" });
    _ = try environment.checkModule(std.testing.allocator, "tests/feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias", .{ .message = "root that has ended", .file = "main.rg" });
    _ = try environment.checkModule(std.testing.allocator, "tests/feature_tests/modules/28X_imported_abstract_input_requires_implementation", .{ .message = "contract constraint 'ExampleAbstract'", .file = "main.rg" });
    _ = try environment.checkModule(std.testing.allocator, "tests/feature_tests/modules/17_multi_file_module_forward_calls", null);
}

test "real core environment accepts explicit allocator dependencies and selected imports" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "allocator_dependencies",
        .files = &.{.{ .path = "main.rg", .code =
        \\main := (.system: System) -> (.status_code: Int32 = 0) {
        \\    c_allocator ::= CAllocator(.ffi = system.ffi)
        \\    page_allocator ::= PageAllocator(.memory = system.memory)
        \\    general_allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
        \\}
        }},
    });
    _ = try environment.checkModule(std.testing.allocator, "tests/feature_tests/execution/110X_computed_import_cycle", .{ .message = "import cycle detected after compile-time selection" });
}

const partitioned_outcome_prefix =
    \\Owner := (.value: Int32)
    \\Outcome := (..changed, ..unchanged)
    \\implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})
;
const partitioned_outcome_body =
    \\mutate := (.self: $&Owner, .fail: Bool) -> (.result: Outcome) {
    \\    if fail {
    \\        result = ..unchanged
    \\    } else {
    \\        deinit(.self = self)
    \\        self&= (.value = 2)
    \\        result = ..changed
    \\    }
;
const partitioned_outcome_main =
    \\main := () -> (.status_code: Int32 = 0) {
    \\    owner :: Owner = (.value = 1)
    \\    observed ::= &owner
    \\    match mutate(.self = $&owner, .fail = true) {
;

test "outcome partitions preserve unchanged exits without reviving changed storage" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    const good = partitioned_outcome_prefix ++ "\n" ++ partitioned_outcome_body ++ "\n}\n" ++ partitioned_outcome_main ++
        \\        ..changed {}
        \\        ..unchanged { status_code = observed&.value }
        \\    }
        \\}
    ;
    _ = try environment.check(.{ .name = "outcome_partition_preserved", .files = &.{.{ .path = "main.rg", .code = good }} });
    const changed = partitioned_outcome_prefix ++ "\n" ++ partitioned_outcome_body ++ "\n}\n" ++ partitioned_outcome_main ++
        \\        ..changed { status_code = observed&.value }
        \\        ..unchanged {}
        \\    }
        \\}
    ;
    _ = try environment.check(.{ .name = "outcome_partition_changed", .files = &.{.{ .path = "main.rg", .code = changed }}, .diagnostic = .{ .message = "reference depends on a root that has ended", .file = "main.rg" } });
    const overwritten = partitioned_outcome_prefix ++ "\n" ++ partitioned_outcome_body ++ "\n    result = ..unchanged\n}\n" ++ partitioned_outcome_main ++
        \\        ..changed {}
        \\        ..unchanged { status_code = observed&.value }
        \\    }
        \\}
    ;
    _ = try environment.check(.{ .name = "outcome_partition_overwritten", .files = &.{.{ .path = "main.rg", .code = overwritten }}, .diagnostic = .{ .message = "reference depends on a root that has ended", .file = "main.rg" } });
    const historical = partitioned_outcome_prefix ++ "\n" ++ partitioned_outcome_body ++ "\n}\n" ++
        \\main := () -> (.status_code: Int32 = 0) {
        \\    owner :: Owner = (.value = 1)
        \\    observed ::= &owner
        \\    deinit(.self = $&owner)
        \\    owner = (.value = 3)
        \\    match mutate(.self = $&owner, .fail = true) {
        \\        ..changed {}
        \\        ..unchanged { status_code = observed&.value }
        \\    }
        \\}
    ;
    _ = try environment.check(.{ .name = "outcome_partition_historical", .files = &.{.{ .path = "main.rg", .code = historical }}, .diagnostic = .{ .message = "reference depends on a root that has ended", .file = "main.rg" } });
    const indirect = partitioned_outcome_prefix ++ "\n" ++ partitioned_outcome_body ++ "\n    selected ::= $&result\n    selected&= ..unchanged\n}\n" ++ partitioned_outcome_main ++
        \\        ..changed {}
        \\        ..unchanged { status_code = observed&.value }
        \\    }
        \\}
    ;
    _ = try environment.check(.{ .name = "outcome_partition_indirect", .files = &.{.{ .path = "main.rg", .code = indirect }}, .diagnostic = .{ .message = "reference depends on a root that has ended", .file = "main.rg" } });
}
