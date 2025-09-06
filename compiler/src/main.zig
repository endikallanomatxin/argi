const std = @import("std");
const build_cmd = @import("commands/build.zig");
const lsp_cmd = @import("commands/lsp.zig");

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch return;
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: argi <command> [file] [options]\n", .{});
        std.debug.print("Available commands:\n", .{});
        std.debug.print("  build <file.rg> [flags]  - Compile program to a binary\n", .{});
        std.debug.print("  lsp                       - Start LSP server\n", .{});
        std.debug.print("\nBuild flags (on build error):\n", .{});
        std.debug.print("  --on-build-error-show-cascade          Print all cascading diagnostics\n", .{});
        std.debug.print("  --on-build-error-show-syntax-tree      Print the syntax tree\n", .{});
        std.debug.print("  --on-build-error-show-semantic-graph   Print the semantic graph\n", .{});
        std.debug.print("  --on-build-error-show-token-list      Print the token list\n", .{});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: file path required\n", .{});
            return;
        }
        const build_args = args[2..];
        build_cmd.compile(build_args) catch |err| {
            std.debug.print("Build error: {any}\n", .{err});
            return;
        };
    } else if (std.mem.eql(u8, command, "lsp")) {
        try lsp_cmd.start();
    } else {
        std.debug.print("Error: unknown command\n", .{});
    }
}
