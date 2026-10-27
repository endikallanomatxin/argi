const std = @import("std");
const support = @import("frontend_test_support.zig");

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
