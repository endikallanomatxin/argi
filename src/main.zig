const std = @import("std");
const build_cmd = @import("0_commands/build.zig");
const init_cmd = @import("0_commands/init.zig");
const lsp_cmd = @import("0_commands/lsp.zig");
const run_cmd = @import("0_commands/run.zig");
const test_cmd = @import("0_commands/test.zig");

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch return;
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: argi <command> [module-directory] [options]\n", .{});
        std.debug.print("Available commands:\n", .{});
        std.debug.print("  build <directory> [flags] - Compile a folder module to a binary\n", .{});
        std.debug.print("  init <project|module> <directory> - Create a starter scaffold\n", .{});
        std.debug.print("  lsp                       - Start LSP server\n", .{});
        std.debug.print("  run <directory> [build flags] - Build a folder module and run it\n", .{});
        std.debug.print("  test <directory> [--filter <name>] - Build and run native Argi tests\n", .{});
        std.debug.print("\nBuild flags (on build error):\n", .{});
        std.debug.print("  --on-build-error-show-cascade          Print all cascading diagnostics\n", .{});
        std.debug.print("  --on-build-error-show-syntax-tree      Print the syntax tree\n", .{});
        std.debug.print("  --on-build-error-show-semantic-graph   Print the semantic graph\n", .{});
        std.debug.print("  --on-build-error-show-token-list      Print the token list\n", .{});
        std.debug.print("  --time-phases                         Print compilation timings by phase\n", .{});
        std.debug.print("  --output <path>                       Write the final binary there\n", .{});
        std.debug.print("  --emit-llvm <path>                    Write the emitted LLVM IR there\n", .{});
        std.debug.print("  --emit-obj <path>                     Write the object file there as an extra output\n", .{});
        std.debug.print("  --just-emit-obj <path>                Emit an object file there and skip final linking\n", .{});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: module directory required\n", .{});
            return;
        }
        const build_args = args[2..];
        build_cmd.compile(build_args) catch |err| {
            std.debug.print("Build error: {any}\n", .{err});
            return err;
        };
    } else if (std.mem.eql(u8, command, "init")) {
        if (args.len < 4) {
            std.debug.print("Error: init requires <project|module> and <directory>\n", .{});
            return;
        }
        init_cmd.run(args[2..4]) catch |err| {
            std.debug.print("Init error: {any}\n", .{err});
            return err;
        };
    } else if (std.mem.eql(u8, command, "lsp")) {
        try lsp_cmd.start();
    } else if (std.mem.eql(u8, command, "run")) {
        if (args.len < 3) {
            std.debug.print("Error: module directory required\n", .{});
            return;
        }
        const exit_code = run_cmd.run(args[2..]) catch |err| {
            std.debug.print("Run error: {any}\n", .{err});
            return err;
        };
        std.process.exit(exit_code);
    } else if (std.mem.eql(u8, command, "test")) {
        if (args.len < 3) {
            std.debug.print("Error: module directory required\n", .{});
            return;
        }
        const exit_code = test_cmd.run(args[2..]) catch |err| {
            std.debug.print("Test error: {any}\n", .{err});
            return err;
        };
        std.process.exit(exit_code);
    } else {
        std.debug.print("Error: unknown command\n", .{});
    }
}
