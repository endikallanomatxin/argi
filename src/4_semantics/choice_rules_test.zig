const std = @import("std");
const support = @import("frontend_test_support.zig");

test "choice missing payload" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "choice_missing_payload",
        .files = &.{.{ .path = "main.rg", .code =
        \\Result: Type = (
        \\    ..ok(.value: Int32),
        \\    ..error(.code: UnicodeScalar),
        \\)
        \\
        \\main := () -> (.status_code: Int32)  {
        \\    value: Result = ..ok
        \\    status_code = 0
        \\}
        }},
        .diagnostic = .{ .message = "choice variant '..ok' requires a payload", .file = "main.rg", .marker = "..ok\n", .exact = true },
    });
}

test "choice payload access without payload" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "choice_payload_access_without_payload",
        .files = &.{.{ .path = "main.rg", .code =
        \\Direction : Type = (
        \\    ..north,
        \\    ..south,
        \\)
        \\
        \\main := () -> (.status_code: Int32)  {
        \\    value : Direction = ..north
        \\    payload := value..north
        \\    status_code = 0
        \\}
        }},
        .diagnostic = .{ .message = "choice variant '..north' has no payload", .file = "main.rg", .marker = "north\n    status_code", .exact = true },
    });
}

test "match non choice" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "match_non_choice",
        .files = &.{.{ .path = "main.rg", .code =
        \\main := () -> (.status_code: Int32)  {
        \\    value : Int32 = 42
        \\
        \\    match value {
        \\        ..some payload {
        \\            status_code = payload.value
        \\        }
        \\    }
        \\}
        }},
        .diagnostic = .{ .message = "match expects a choice value, found 'Int32'", .file = "main.rg", .marker = "value {", .exact = true },
    });
}

test "match bind payload without payload" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "match_bind_payload_without_payload",
        .files = &.{.{ .path = "main.rg", .code =
        \\Direction : Type = (
        \\    ..north,
        \\    ..south,
        \\)
        \\
        \\main := () -> (.status_code: Int32)  {
        \\    value : Direction = ..south
        \\
        \\    match value {
        \\        ..north payload {
        \\            status_code = 1
        \\        }
        \\        ..south {
        \\            status_code = 0
        \\        }
        \\    }
        \\}
        }},
        .diagnostic = .{ .message = "choice variant '..north' has no payload to bind", .file = "main.rg", .marker = "payload {", .exact = true },
    });
}

test "errable match unknown variant" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "errable_match_unknown_variant",
        .files = &.{.{ .path = "main.rg", .code =
        \\..test_error
        \\
        \\main := () -> (.status_code: Int32)  {
        \\    value : Errable#(.t: Int32, .reasons: (..test_error)) = ..ok 7
        \\
        \\    match value {
        \\        ..none {
        \\            return 0
        \\        }
        \\        ..ok payload {
        \\            return payload
        \\        }
        \\        ..error err {
        \\            use err
        \\            return 0
        \\        }
        \\    }
        \\}
        }},
        .diagnostic = .{ .message = "choice type 'Errable#(.t: Int32, .reasons: (..test_error))' has no variant '..none'", .file = "main.rg", .marker = "none {", .exact = true },
    });
}

test "match omit payload pattern" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "match_omit_payload_pattern",
        .files = &.{.{ .path = "main.rg", .code =
        \\Result: Type = (
        \\    ..ok(.value: Int32),
        \\    ..error(.code: UnicodeScalar),
        \\)
        \\
        \\main := () -> (.status_code: Int32) {
        \\    value: Result = ..error(.code = 'E')
        \\
        \\    match value {
        \\        ..ok payload {
        \\            status_code = payload.value
        \\        }
        \\        ..error {
        \\            status_code = 1
        \\        }
        \\    }
        \\}
        }},
        .diagnostic = .{ .message = "choice variant '..error' carries a payload and match must bind it explicitly; use '..error _' to ignore it", .file = "main.rg", .marker = "error {", .exact = true },
    });
}

test "match value noncopyable payload" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "match_value_noncopyable_payload",
        .files = &.{.{ .path = "main.rg", .code =
        \\Token := (
        \\    .value : Int32,
        \\)
        \\
        \\implement Deinit#(Token) (
        \\    .deinit = (.self: $&Token) -> () {
        \\
        \\    }
        \\)
        \\
        \\Result: Type = (
        \\    ..ok(.token: Token),
        \\    ..error,
        \\)
        \\
        \\main := () -> (.status_code: Int32) {
        \\    value: Result = ..ok(.token = Token(.value = 7))
        \\
        \\    match value {
        \\        ..ok payload {
        \\            status_code = payload.token.value
        \\        }
        \\        ..error {
        \\            status_code = 1
        \\        }
        \\    }
        \\}
        }},
        .diagnostic = .{ .message = "type '<anonymous>' cannot be copied implicitly; use '~value' to transfer ownership", .file = "main.rg", .marker = "payload {", .exact = true },
    });
}
test "match explicitly ignores a choice payload" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{
        .name = "match_ignore_payload",
        .files = &.{.{ .path = "main.rg", .code =
        \\Result: Type = (
        \\    ..ok(.value: Int32),
        \\    ..error(.code: UnicodeScalar),
        \\)
        \\
        \\main := () -> (.status_code: Int32) {
        \\    value: Result = ..error(.code = 'E')
        \\
        \\    match value {
        \\        ..ok payload {
        \\            status_code = payload.value
        \\        }
        \\        ..error _ {
        \\            status_code = 1
        \\        }
        \\    }
        \\}
        }},
    });
}
