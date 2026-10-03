const std = @import("std");
const builtin = @import("builtin");

/// Compilation configuration belongs to semantic artifacts, not process-global
/// state. The compact identity is persisted with ModuleSG and included in reuse
/// keys; consumers derive C data-model and ABI decisions from the same value.
pub const Config = struct {
    arch: std.Target.Cpu.Arch = builtin.cpu.arch,
    os: std.Target.Os.Tag = builtin.os.tag,
    abi: std.Target.Abi = builtin.abi,

    pub fn parse(text: []const u8) !Config {
        if (std.mem.eql(u8, text, "native")) return .{};
        var parts = std.mem.splitScalar(u8, text, '-');
        const arch = std.meta.stringToEnum(std.Target.Cpu.Arch, parts.next() orelse return error.InvalidTarget) orelse return error.InvalidTarget;
        const os = std.meta.stringToEnum(std.Target.Os.Tag, parts.next() orelse return error.InvalidTarget) orelse return error.InvalidTarget;
        const abi = std.meta.stringToEnum(std.Target.Abi, parts.next() orelse return error.InvalidTarget) orelse return error.InvalidTarget;
        if (parts.next() != null) return error.InvalidTarget;
        const result: Config = .{ .arch = arch, .os = os, .abi = abi };
        if (!result.isNative() and !(os == .linux and abi == .gnu and (arch == .x86_64 or arch == .aarch64))) return error.UnsupportedTarget;
        return result;
    }

    pub fn isNative(self: Config) bool {
        return std.meta.eql(self, Config{});
    }

    pub fn stdTarget(self: Config) std.Target {
        var target = builtin.target;
        target.os = .{ .tag = self.os, .version_range = std.Target.Os.VersionRange.default(self.arch, self.os, self.abi) };
        target.ofmt = std.Target.ObjectFormat.default(self.os, self.arch);
        target.dynamic_linker = .none;
        target.abi = self.abi;
        target.cpu = std.Target.Cpu.baseline(self.arch, target.os);
        return target;
    }

    pub fn pointerBytes(self: Config) u64 {
        return self.stdTarget().ptrBitWidth() / 8;
    }
};

test "target configuration selects the C data model independently of the host" {
    const target = try Config.parse("aarch64-linux-gnu");
    try std.testing.expectEqual(std.Target.Cpu.Arch.aarch64, target.stdTarget().cpu.arch);
    try std.testing.expectEqual(@as(u64, 8), target.pointerBytes());
    try std.testing.expectError(error.UnsupportedTarget, Config.parse("wasm32-freestanding-none"));
    try std.testing.expectError(error.InvalidTarget, Config.parse("aarch64-linux-gnu-extra"));
}
