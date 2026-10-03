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

    // LLVM's build host is not the application's ABI. In particular, an MSVC
    // LLVM DLL can emit MinGW objects for a compiler built against the GNU CRT.
    pub fn llvmTriple(self: Config, allocator: std.mem.Allocator) ![:0]u8 {
        const arch = if (self.arch == .x86) "i386" else @tagName(self.arch);
        if (self.os.isDarwin()) return std.fmt.allocPrintSentinel(allocator, "{s}-apple-darwin", .{arch}, 0);
        const vendor = if (self.os == .windows) "pc" else "unknown";
        return std.fmt.allocPrintSentinel(allocator, "{s}-{s}-{s}-{s}", .{ arch, vendor, @tagName(self.os), @tagName(self.abi) }, 0);
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

test "LLVM triples derive from the application target rather than LLVM's host" {
    const allocator = std.testing.allocator;
    const cases = [_]struct { target: Config, triple: []const u8 }{
        .{ .target = .{ .arch = .x86_64, .os = .windows, .abi = .gnu }, .triple = "x86_64-pc-windows-gnu" },
        .{ .target = .{ .arch = .x86_64, .os = .windows, .abi = .msvc }, .triple = "x86_64-pc-windows-msvc" },
        .{ .target = .{ .arch = .aarch64, .os = .linux, .abi = .gnu }, .triple = "aarch64-unknown-linux-gnu" },
        .{ .target = .{ .arch = .aarch64, .os = .macos, .abi = .none }, .triple = "aarch64-apple-darwin" },
    };
    for (cases) |case| {
        const triple = try case.target.llvmTriple(allocator);
        defer allocator.free(triple);
        try std.testing.expectEqualStrings(case.triple, triple);
    }
}
