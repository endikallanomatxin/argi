const std = @import("std");
const support = @import("frontend_test_support.zig");

test "array view iteration supports borrowed records and enforces access modes" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{ .name = "borrowed_record_length", .files = &.{.{ .path = "main.rg", .code =
        \\Spec := (.name: StringView, .dependencies: ArrayView#(StringView))
        \\implement ImplicitlyCopyable#(Spec) ()
        \\inspect := (.specs: ArrayView#(Spec)) -> (.found: Bool = false) {
        \\    for spec in specs { if spec.name == "sample" { found = true } }
        \\}
        \\main := () -> (.status_code: Int32 = 1) {
        \\    assume error_tracer ::= $&noop_error_tracer
        \\    names: [1]StringView = ("other")
        \\    specs: [1]Spec = ((.name = "sample", .dependencies = view(&names)))
        \\    if inspect(.specs = view(&specs)).found { status_code = 0 }
        \\}
    }} });
    _ = try environment.check(.{ .name = "readonly_view_mutation", .files = &.{.{ .path = "main.rg", .code =
        \\main := () -> () {
        \\    values: [1]Int32 = (1)
        \\    readonly ::= view(&values)
        \\    for $&value in readonly { value&= 2 }
        \\}
    }}, .diagnostic = .{ .message = "for expects a type implementing contract 'MutableReferenceIterable'" } });
    _ = try environment.check(.{ .name = "noncopyable_view_value_iteration", .files = &.{.{ .path = "main.rg", .code =
        \\Resource := (.value: Int32)
        \\implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})
        \\main := () -> () {
        \\    values: [1]Resource = ((.value = 1))
        \\    readonly ::= view(&values)
        \\    for value in readonly { }
        \\}
    }}, .diagnostic = .{ .message = "for expects a type implementing contract 'Iterable'" } });
}

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

test "plain fallibility does not require diagnostic capabilities" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    try std.testing.expectEqual(@as(i128, 104), try environment.execute(.{ .name = "plain_text_read_without_tracer", .files = &.{.{ .path = "main.rg", .code =
        \\read := (.text: StringView) -> !UInt8 {
        \\    byte ::= bytes_get(.view = &text, .index = 0)!
        \\    result = ..ok byte
        \\}
        \\main := () -> (.status_code: Int32) {
        \\    byte ::= unwrap_or_abort(.value = read(.text = "hello"))
        \\    status_code = byte | convert#(.to: Int32)(_)
        \\}
    }} }, .{}));
}

test "missing input diagnostics share ordinary and generic record matching" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    const generic =
        \\inspect := #(.T: Type) (.value: T, .context: Bool) -> () {}
        \\
    ;
    for ([_][]const u8{
        "inspect(.value = 42)",
        "inspect#(.T: Int32)(.value = 42)",
    }, 0..) |call, index| {
        const source = try std.fmt.allocPrint(std.testing.allocator, "{s}main := () -> () {{ {s} }}", .{ generic, call });
        defer std.testing.allocator.free(source);
        _ = try environment.check(.{ .name = if (index == 0) "missing_inferred_input" else "missing_explicit_input", .files = &.{.{ .path = "main.rg", .code = source }}, .diagnostic = .{ .message = "call to 'inspect' is missing required argument '.context'" } });
    }
    _ = try environment.check(.{ .name = "missing_ordinary_input", .files = &.{.{ .path = "main.rg", .code =
        \\inspect := (.value: Int32, .context: Bool) -> () {}
        \\main := () -> () { inspect(.value = 42) }
    }}, .diagnostic = .{ .message = "call to 'inspect' is missing required argument '.context'" } });
    _ = try environment.check(.{ .name = "mismatch_before_missing_input", .files = &.{.{ .path = "main.rg", .code = generic ++
        \\main := () -> () { inspect#(.T: Int32)(.value = true) }
    }}, .diagnostic = .{ .message = "no generic function named 'inspect' accepts arguments", .forbidden = &.{"missing required argument"} } });
    _ = try environment.check(.{ .name = "ordinary_assumed_and_default_inputs", .files = &.{.{ .path = "main.rg", .code = generic ++
        \\with_default := (.context: Bool = false) -> () {}
        \\main := () -> () {
        \\    assume context := true
        \\    inspect(.value = 42)
        \\    with_default()
        \\}
    }} });
}

test "error tracing requires explicit promotion and preserves borrowed lifetimes" {
    var environment = try support.Environment.init(std.testing.allocator, std.testing.io);
    defer environment.deinit();
    _ = try environment.check(.{ .name = "plain_error_requires_explicit_promotion", .files = &.{.{ .path = "main.rg", .code =
        \\plain := () -> !Int32 { result = ..error (.reason = ..invalid_input) }
        \\traced := () -> !!Int32 { value ::= plain()!; result = ..ok value }
        \\main := () -> () { traced() }
    }}, .diagnostic = .{ .message = "propagating a plain error into a traced result requires '!! context'" } });
    _ = try environment.check(.{ .name = "trace_cannot_be_discarded_by_propagation", .files = &.{.{ .path = "main.rg", .code =
        \\traced := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!Int32 {
        \\    assume error_tracer
        \\    result = ..error (.reason = ..invalid_input)
        \\}
        \\plain := () -> !Int32 {
        \\    value ::= traced(.error_tracer = $&noop_error_tracer)!
        \\    result = ..ok value
        \\}
        \\main := () -> () { plain() }
    }}, .diagnostic = .{ .message = "cannot discard an error trace during propagation" } });
    _ = try environment.check(.{ .name = "trace_promotion_requires_lexical_capability", .files = &.{.{ .path = "main.rg", .code =
        \\plain := () -> !Int32 { result = ..error (.reason = ..invalid_input) }
        \\traced := () -> !!Int32 { value ::= plain()!! "context"; result = ..ok value }
        \\main := () -> () { traced() }
    }}, .diagnostic = .{ .message = "missing required argument '.error_tracer'" } });
    _ = try environment.check(.{ .name = "local_tracer_cannot_escape_in_direct_error", .files = &.{.{ .path = "main.rg", .code =
        \\traced := () -> !!Int32 {
        \\    local: NoopErrorTracer = ()
        \\    handle ::= to_virtual#(ErrorTracer)($&local)
        \\    assume error_tracer ::= $&handle
        \\    result = ..error (.reason = ..invalid_input)
        \\}
        \\main := () -> () { traced() }
    }}, .diagnostic = .{ .message = "function output cannot depend on a local storage generation" } });
    _ = try environment.check(.{ .name = "local_tracer_cannot_escape_in_promotion", .files = &.{.{ .path = "main.rg", .code =
        \\plain := () -> !Int32 { result = ..error (.reason = ..invalid_input) }
        \\traced := () -> !!Int32 {
        \\    local: NoopErrorTracer = ()
        \\    handle ::= to_virtual#(ErrorTracer)($&local)
        \\    assume error_tracer ::= $&handle
        \\    value ::= plain()!! "context"
        \\    result = ..ok value
        \\}
        \\main := () -> () { traced() }
    }}, .diagnostic = .{ .message = "function output cannot depend on a local storage generation" } });
}
