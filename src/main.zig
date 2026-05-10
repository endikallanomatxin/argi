const std = @import("std");
const build_cmd = @import("0_commands/build.zig");
const init_cmd = @import("0_commands/init.zig");
const lsp_cmd = @import("0_commands/lsp.zig");
const run_cmd = @import("0_commands/run.zig");
const test_cmd = @import("0_commands/test.zig");
const argi_version = @import("0_commands/version.zig");

fn exitCommandError(prefix: []const u8, err: anyerror) noreturn {
    if (err != error.CompilationFailed) {
        std.debug.print("{s}: {s}\n", .{ prefix, @errorName(err) });
    }
    std.process.exit(1);
}

fn exitRunError(err: anyerror) noreturn {
    switch (err) {
        error.RunOutputFlagUnsupported => {
            std.debug.print("Run error: --output is not supported by argi run; use argi build --output and execute the binary manually\n", .{});
        },
        error.RunEmitLlvmUnsupported => {
            std.debug.print("Run error: --emit-llvm is not supported by argi run; use argi build --emit-llvm and execute the binary manually\n", .{});
        },
        error.RunEmitObjectUnsupported => {
            std.debug.print("Run error: object emission flags are not supported by argi run; use argi build and execute the binary manually\n", .{});
        },
        else => exitCommandError("Run error", err),
    }
    std.process.exit(1);
}

fn printHelp() void {
    std.debug.print("Usage: argi <command> [arguments] [options]\n", .{});
    std.debug.print("\nCommands:\n", .{});
    std.debug.print("  build [path] [flags]                   Build the current package, package path, or module path\n", .{});
    std.debug.print("  run [executable] [build flags]         Build and run the default or selected executable\n", .{});
    std.debug.print("  test <directory> [flags]               Build and run native Argi tests\n", .{});
    std.debug.print("  init <name>                            Create an executable package\n", .{});
    std.debug.print("  init --lib <name>                      Create a library package\n", .{});
    std.debug.print("  lsp                                    Start the language server\n", .{});
    std.debug.print("  version                                Show the Argi version\n", .{});
    std.debug.print("  help                                   Show this help\n", .{});
    std.debug.print("\nBuild flags:\n", .{});
    std.debug.print("  --output <path>                        Write the final binary there\n", .{});
    std.debug.print("  --emit-llvm <path>                     Write the emitted LLVM IR there\n", .{});
    std.debug.print("  --emit-obj <path>                      Write the object file there as an extra output\n", .{});
    std.debug.print("  --just-emit-obj <path>                 Emit an object file there and skip final linking\n", .{});
    std.debug.print("  --sysroot <path>                       Use an Argi installation prefix for core\n", .{});
    std.debug.print("  --entry <name>                         Build a named executable from argi.toml\n", .{});
    std.debug.print("  --time-phases                          Print compilation timings by phase\n", .{});
    std.debug.print("\nTest flags:\n", .{});
    std.debug.print("  --filter <name>                        Run only tests whose name contains this text\n", .{});
    std.debug.print("\nBuild diagnostic flags:\n", .{});
    std.debug.print("  --on-build-error-show-cascade          Print all cascading diagnostics\n", .{});
    std.debug.print("  --on-build-error-show-syntax-tree      Print the syntax tree\n", .{});
    std.debug.print("  --on-build-error-show-semantic-graph   Print the semantic graph\n", .{});
    std.debug.print("  --on-build-error-show-token-list       Print the token list\n", .{});
}

fn isHelpArg(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "help") or
        std.mem.eql(u8, arg, "--help") or
        std.mem.eql(u8, arg, "-h");
}

fn isVersionArg(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "version") or
        std.mem.eql(u8, arg, "--version") or
        std.mem.eql(u8, arg, "-V");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2 or isHelpArg(args[1])) {
        printHelp();
        return;
    }

    const command = args[1];

    if (isVersionArg(command)) {
        std.debug.print("argi {s}\n", .{argi_version.current});
        return;
    }

    if (std.mem.eql(u8, command, "build")) {
        const build_args = args[2..];
        build_cmd.compile(io, init.environ_map, build_args) catch |err| {
            exitCommandError("Build error", err);
        };
    } else if (std.mem.eql(u8, command, "init")) {
        if (args.len < 3) {
            std.debug.print("Error: init requires <name> or --lib <name>\n", .{});
            std.process.exit(1);
        }
        init_cmd.run(io, args[2..]) catch |err| {
            exitCommandError("Init error", err);
        };
    } else if (std.mem.eql(u8, command, "lsp")) {
        lsp_cmd.start(io) catch |err| {
            exitCommandError("LSP error", err);
        };
    } else if (std.mem.eql(u8, command, "run")) {
        const exit_code = run_cmd.run(io, init.environ_map, args[2..]) catch |err| {
            exitRunError(err);
        };
        std.process.exit(exit_code);
    } else if (std.mem.eql(u8, command, "test")) {
        if (args.len < 3) {
            std.debug.print("Error: module directory required\n", .{});
            std.process.exit(1);
        }
        const exit_code = test_cmd.run(io, init.environ_map, args[2..]) catch |err| {
            exitCommandError("Test error", err);
        };
        std.process.exit(exit_code);
    } else {
        std.debug.print("Error: unknown command '{s}'\n\n", .{command});
        printHelp();
        std.process.exit(1);
    }
}
