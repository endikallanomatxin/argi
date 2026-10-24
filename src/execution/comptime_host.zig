const std = @import("std");
const host = @import("host.zig");
const p = @import("../4_semantics/primitives/schema.zig");

// Bootstrap only. These adapters expose no filesystem, environment, input,
// network, process or entropy reads. Unregistered operations fail before run.
// Each evaluation owns its endpoint adapter; no host handle enters frozen output.
pub const Environment = struct {
    output: @import("host_output.zig").Output,

    fn zero(_: ?*anyopaque, _: []const i128, outputs: []i128) !void {
        if (outputs.len != 0) outputs[0] = 0;
    }
    fn pageSize(_: ?*anyopaque, _: []const i128, outputs: []i128) !void {
        outputs[0] = std.heap.pageSize();
    }

    pub fn bindings(self: *Environment) [9]host.Binding {
        const endpoints = self.output.bindings();
        const native = comptime p.integerRangeForWidth(@bitSizeOf(usize), false);
        const signed = comptime p.integerRangeForWidth(32, true);
        return .{
            endpoints[0],
            endpoints[1],
            endpoints[2],
            endpoints[3],
            .{ .symbol = "_memory_getpagesize", .inputs = &.{}, .outputs = &.{native}, .call = pageSize },
            .{ .symbol = "argi_runtime_argc", .inputs = &.{}, .outputs = &.{native}, .call = zero },
            .{ .symbol = "argi_runtime_argv", .inputs = &.{}, .outputs = &.{native}, .call = zero },
            .{ .symbol = "_argi_network_init", .inputs = &.{}, .outputs = &.{signed}, .call = zero },
            .{ .symbol = "_argi_network_deinit", .inputs = &.{}, .outputs = &.{}, .call = zero },
        };
    }
};
