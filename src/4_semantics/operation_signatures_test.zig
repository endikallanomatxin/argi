const std = @import("std");
const support = @import("frontend_test_support.zig");

const inputs =
    \\Inputs := #(.T: Type) (
    \\    .self: &T
    \\    .value: Array#(.t: UInt8, .n = #run () -> (.n: UIntNative) { n = 2 })
    \\)
    \\Thing := (.value: Int32)
    \\
;
const caller =
    \\main := () -> (.status_code: Int32) {
    \\    thing: Thing = (.value = 42)
    \\    bytes: [2]UInt8 = (1, 2)
    \\    status_code = read(.self = &thing, .value = bytes)
    \\}
;

test "contract operation signatures suspend compile-time inputs like ordinary functions" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{ .name = "ordinary_staged_signature", .files = &.{.{ .path = "main.rg", .code = inputs ++
        \\read := Inputs#(Thing) -> (.value: Int32) { value = self&.value }
        \\
    ++ caller }} });
    _ = try environment.check(.{ .name = "contract_staged_signature", .files = &.{.{ .path = "main.rg", .code = inputs ++
        \\Read#(.T: Type): Contract = (.read: Inputs#(T) -> (.value: Int32))
        \\implement Read#(Thing) (
        \\    .read = Inputs#(Thing) -> (.value: Int32) { value = self&.value }
        \\)
        \\
    ++ caller }} });
}

test "contract operation output signatures resume staged generic dimensions" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    const result = try environment.execute(.{ .name = "staged_output_signature", .files = &.{.{ .path = "main.rg", .code =
        \\Outputs := #(.T: Type) (
        \\    .bytes: Array#(.t: UInt8, .n = #run () -> (.n: UIntNative) { n = 2 })
        \\    .tag: Int32
        \\)
        \\Thing := (.value: Int32)
        \\Read#(.T: Type): Contract = (.read: (.self: &T) -> Outputs#(T))
        \\implement Read#(Thing) (
        \\    .read = (.self: &Thing) -> Outputs#(Thing) { bytes = (20, 22) tag = self&.value }
        \\)
        \\main := () -> (.status_code: Int32) {
        \\    thing: Thing = (.value = 42)
        \\    result ::= read(.self = &thing)
        \\    if result.bytes[0] != 20 or result.bytes[1] != 22 { abort }
        \\    status_code = result.tag
        \\}
    }} }, .{});
    try std.testing.expectEqual(@as(i128, 42), result);
}

test "contract operation selection ignores unrelated unbound signature parameters" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    const result = try environment.execute(.{ .name = "unbound_losing_signature", .files = &.{.{ .path = "main.rg", .code = inputs ++
        \\Read#(.T: Type): Contract = (.read: Inputs#(T) -> (.value: Int32))
        \\UnboundRead#(.T: Type): Contract = (
        \\    .read: #(.Unused: Type) Inputs#(T) -> (.value: Int32)
        \\)
        \\implement Read#(Thing) (
        \\    .read = Inputs#(Thing) -> (.value: Int32) { value = self&.value }
        \\)
        \\implement UnboundRead#(Thing) (
        \\    .read = #(.Unused: Type) Inputs#(Thing) -> (.value: Int32) { value = 7 }
        \\)
        \\
    ++ caller }} }, .{});
    try std.testing.expectEqual(@as(i128, 42), result);
}

test "contract operation signatures report failed compile-time dimensions" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{ .name = "failed_staged_signature", .files = &.{.{ .path = "main.rg", .code =
        \\Inputs := #(.T: Type) (
        \\    .self: &T
        \\    .value: Array#(.t: UInt8, .n = #run () -> (.n: UIntNative) { abort })
        \\)
        \\Thing := (.value: Int32)
        \\Read#(.T: Type): Contract = (.read: Inputs#(T) -> (.value: Int32))
        \\implement Read#(Thing) (
        \\    .read = Inputs#(Thing) -> (.value: Int32) { value = 0 }
        \\)
        \\main := () -> (.status_code: Int32 = 0) {}
    }}, .diagnostic = .{ .message = "#run evaluation aborted", .file = "main.rg" } });
}

test "a losing invalid signature specialization cannot poison a valid operation" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    const source = inputs ++
        \\SmallRead#(.T: Type): Contract = (
        \\    .read: #(.n: Int32) (
        \\        .self: &T
        \\        .value: [n]UInt8
        \\        .padding: Array#(.t: UInt8, .n = [n - 4]) = ()
        \\    ) -> (.value: Int32)
        \\)
        \\implement SmallRead#(Thing) (
        \\    .read = #(.n: Int32) (
        \\        .self: &Thing
        \\        .value: [n]UInt8
        \\        .padding: Array#(.t: UInt8, .n = [n - 4]) = ()
        \\    ) -> (.value: Int32) { value = 7 }
        \\)
        \\Read#(.T: Type): Contract = (.read: Inputs#(T) -> (.value: Int32))
        \\implement Read#(Thing) (
        \\    .read = Inputs#(Thing) -> (.value: Int32) { value = self&.value }
        \\)
        \\
    ++ caller;
    try std.testing.expectEqual(@as(i128, 42), try environment.execute(.{ .name = "invalid_losing_signature", .files = &.{.{ .path = "main.rg", .code = source }} }, .{}));
}
