const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;

const LinkError = error{
    TargetLookupFailed,
    TargetMachineFailed,
    EmitFailedWithMessage,
    LinkFailed,
};

// This selects LLVM's machine-code pipeline only. Argi does not yet run an
// LLVM IR optimization pipeline; release mode can add that independently.
pub const OptimizationMode = enum {
    development,
    release,

    pub fn llvmCodeGenLevel(self: OptimizationMode) c.LLVMCodeGenOptLevel {
        return switch (self) {
            .development => c.LLVMCodeGenLevelNone,
            .release => c.LLVMCodeGenLevelDefault,
        };
    }

    pub fn llvmCodeGenLevelName(self: OptimizationMode) []const u8 {
        return switch (self) {
            .development => "none",
            .release => "default",
        };
    }
};

fn createTargetMachine(
    module: llvm.c.LLVMModuleRef,
    triple: [:0]const u8,
    optimization_mode: OptimizationMode,
) !llvm.c.LLVMTargetMachineRef {
    if (c.LLVMInitializeNativeTarget() != 0 or c.LLVMInitializeNativeAsmPrinter() != 0)
        return error.LLVMTargetInitFailed;

    var err_ptr: [*c]u8 = null;
    var target_ref: llvm.c.LLVMTargetRef = null;

    if (c.LLVMGetTargetFromTriple(triple, &target_ref, &err_ptr) != 0) {
        std.debug.print("LLVMGetTargetFromTriple failed: {s}\n", .{err_ptr});
        c.LLVMDisposeMessage(err_ptr);
        return LinkError.TargetLookupFailed;
    }

    defer if (err_ptr) |p| c.LLVMDisposeMessage(p);

    const tm = c.LLVMCreateTargetMachine(
        target_ref,
        triple,
        "", // CPU
        "", // features
        optimization_mode.llvmCodeGenLevel(),
        c.LLVMRelocPIC,
        c.LLVMCodeModelDefault,
    ) orelse return error.TargetMachineFailed;

    c.LLVMSetTarget(module, triple);
    return tm;
}

pub fn emitObjectFile(
    module: llvm.c.LLVMModuleRef,
    triple: [:0]const u8,
    obj_output_path: []const u8,
    optimization_mode: OptimizationMode,
) !void {
    const tm = try createTargetMachine(module, triple, optimization_mode);
    defer c.LLVMDisposeTargetMachine(tm);

    var err_ptr: [*c]u8 = null;
    const obj_path_z = try std.heap.c_allocator.dupeZ(u8, obj_output_path);
    defer std.heap.c_allocator.free(obj_path_z);
    if (c.LLVMTargetMachineEmitToFile(
        tm,
        module,
        obj_path_z,
        c.LLVMObjectFile,
        &err_ptr,
    ) != 0) {
        if (err_ptr) |msg| {
            std.debug.print("LLVMTargetMachineEmitToFile failed: {s}\n", .{msg});
            c.LLVMDisposeMessage(msg);
        }
        return error.EmitFailedWithMessage;
    }
}

fn chooseLinkerCommand(cc_env: ?[]const u8) []const u8 {
    if (cc_env) |value| {
        if (value.len != 0) return value;
    }
    return "cc";
}

/// Keep native inputs typed and ordered: archive resolution can depend on the
/// order of files and libraries. Paths and names are separate process arguments,
/// never shell command fragments. Target/toolchain selection can reuse this list.
pub const NativeInput = union(enum) {
    library: []const u8,
    static_library: []const u8,
    shared_library: []const u8,
    search_path: []const u8,
    file: []const u8,
};

fn buildLinkArgv(
    allocator: std.mem.Allocator,
    linker: []const u8,
    obj_path: []const u8,
    output_path: []const u8,
    inputs: []const NativeInput,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ linker, obj_path, "-o", output_path });
    for (inputs) |input| switch (input) {
        .library => |name| {
            try argv.appendSlice(allocator, &.{ "-l", name });
        },
        .search_path => |path| {
            try argv.appendSlice(allocator, &.{ "-L", path });
        },
        .file => |path| try argv.append(allocator, path),
        .static_library, .shared_library => unreachable,
    };
    try argv.append(allocator, "-lc");
    return argv.toOwnedSlice(allocator);
}

// Resolve an explicit mode to an exact artifact before building linker argv.
// This avoids changing the search mode for later libraries or implicit libc.
// Search directories apply to every library, as they do for the native linker.
fn resolveNamedLibrary(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
    linker: []const u8,
    inputs: []const NativeInput,
    name: []const u8,
    shared: bool,
) ![]const u8 {
    if (std.mem.indexOfAny(u8, name, "/\\") != null) {
        std.debug.print("Error: native library name '{s}' contains a path; use --link-file instead.\n", .{name});
        return error.LinkFailed;
    }
    const suffixes: []const []const u8 = if (!shared)
        &.{".a"}
    else if (@import("builtin").os.tag.isDarwin())
        &.{ ".dylib", ".tbd" }
    else
        &.{".so"};
    for (inputs) |input| {
        if (input != .search_path) continue;
        for (suffixes) |suffix| {
            const filename = try std.fmt.allocPrint(allocator, "lib{s}{s}", .{ name, suffix });
            const path = try std.fs.path.resolve(allocator, &.{ input.search_path, filename });
            std.Io.Dir.cwd().access(io, path, .{}) catch continue;
            return try std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
        }
    }
    // Ask the selected C driver about its own toolchain paths rather than
    // hard-coding architecture-specific system library directories.
    for (suffixes) |suffix| {
        const filename = try std.fmt.allocPrint(allocator, "lib{s}{s}", .{ name, suffix });
        const query = try std.fmt.allocPrint(allocator, "-print-file-name={s}", .{filename});
        const result = std.process.run(allocator, io, .{
            .argv = &.{ linker, query },
            .environ_map = environ_map,
        }) catch |err| {
            std.debug.print("Error: cannot query native library paths with '{s}': {s}\n", .{ linker, @errorName(err) });
            return error.LinkFailed;
        };
        const path = std.mem.trim(u8, result.stdout, " \t\r\n");
        if (result.term != .exited or result.term.exited != 0 or
            path.len == 0 or std.mem.eql(u8, path, filename)) continue;
        std.Io.Dir.cwd().access(io, path, .{}) catch continue;
        return try std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator);
    }
    std.debug.print("Error: {s} native library '{s}' was not found; add --library-path or select an exact artifact with --link-file.\n", .{ if (shared) "shared" else "static", name });
    return error.LinkFailed;
}

fn printLinkCommand(argv: []const []const u8) void {
    std.debug.print("  ", .{});
    for (argv, 0..) |arg, idx| {
        if (idx != 0) std.debug.print(" ", .{});
        std.debug.print("{s}", .{arg});
    }
    std.debug.print("\n", .{});
}

fn printCapturedStream(label: []const u8, data: []const u8) void {
    if (data.len == 0) return;
    std.debug.print("{s}:\n{s}\n", .{ label, data });
}

fn printTerm(term: std.process.Child.Term) void {
    switch (term) {
        .exited => |code| std.debug.print("linker exited with code {d}\n", .{code}),
        .signal => |signal| std.debug.print("linker terminated by signal {d}\n", .{signal}),
        .stopped => |signal| std.debug.print("linker stopped by signal {d}\n", .{signal}),
        .unknown => |code| std.debug.print("linker terminated unexpectedly ({d})\n", .{code}),
    }
}

fn printLinkerFailure(
    linker: []const u8,
    argv: []const []const u8,
    result: ?std.process.RunResult,
    spawn_err: ?anyerror,
) void {
    std.debug.print("link failed while running:\n", .{});
    printLinkCommand(argv);
    if (spawn_err) |err| {
        std.debug.print("failed to run C linker/compiler '{s}': {s}\n", .{ linker, @errorName(err) });
        std.debug.print("install a C compiler or set CC=/path/to/compiler\n", .{});
        return;
    }

    if (result) |res| {
        printTerm(res.term);
        printCapturedStream("stdout", res.stdout);
        printCapturedStream("stderr", res.stderr);
    }
}

/// Compiles the `LLVMModuleRef` from `codegen.generate` into an object
/// and links it with the system libc to produce `output_path`.
pub fn linkWithLibc(
    module: llvm.c.LLVMModuleRef,
    triple: [:0]const u8,
    output_path: []const u8,
    allocator: *const std.mem.Allocator,
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
    optimization_mode: OptimizationMode,
    inputs: []const NativeInput,
) !void {
    var obj_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const obj_path = try std.fmt.bufPrint(&obj_path_buf, "{s}.o", .{output_path});
    try emitObjectFile(module, triple, obj_path, optimization_mode);

    const cc_env = if (environ_map) |env_map| env_map.get("CC") else null;
    const linker = chooseLinkerCommand(cc_env);

    var arena = std.heap.ArenaAllocator.init(allocator.*);
    defer arena.deinit();
    const resolved = try arena.allocator().dupe(NativeInput, inputs);
    for (resolved) |*input| switch (input.*) {
        .static_library => |name| input.* = .{ .file = try resolveNamedLibrary(arena.allocator(), io, environ_map, linker, inputs, name, false) },
        .shared_library => |name| input.* = .{ .file = try resolveNamedLibrary(arena.allocator(), io, environ_map, linker, inputs, name, true) },
        else => {},
    };
    const argv = try buildLinkArgv(arena.allocator(), linker, obj_path, output_path, resolved);

    const result = std.process.run(allocator.*, io, .{
        .argv = argv,
        .environ_map = environ_map,
    }) catch |err| {
        printLinkerFailure(linker, argv, null, err);
        return error.LinkFailed;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            printLinkerFailure(linker, argv, result, null);
            return error.LinkFailed;
        },
        else => {
            printLinkerFailure(linker, argv, result, null);
            return error.LinkFailed;
        },
    }
}

test "chooseLinkerCommand prefers CC when provided" {
    try std.testing.expectEqualStrings("cc", chooseLinkerCommand(null));
    try std.testing.expectEqualStrings("cc", chooseLinkerCommand(""));
    try std.testing.expectEqualStrings("clang", chooseLinkerCommand("clang"));
}

test "buildLinkArgv keeps linker object output and libc order" {
    const argv = try buildLinkArgv(std.testing.allocator, "clang", "/tmp/input.o", "/tmp/output", &.{});
    defer std.testing.allocator.free(argv);
    try std.testing.expectEqualStrings("clang", argv[0]);
    try std.testing.expectEqualStrings("/tmp/input.o", argv[1]);
    try std.testing.expectEqualStrings("-o", argv[2]);
    try std.testing.expectEqualStrings("/tmp/output", argv[3]);
    try std.testing.expectEqualStrings("-lc", argv[4]);
}

test "optimization modes select machine code optimization levels" {
    try std.testing.expectEqual(@as(c.LLVMCodeGenOptLevel, c.LLVMCodeGenLevelNone), OptimizationMode.development.llvmCodeGenLevel());
    try std.testing.expectEqual(@as(c.LLVMCodeGenOptLevel, c.LLVMCodeGenLevelDefault), OptimizationMode.release.llvmCodeGenLevel());
    try std.testing.expectEqualStrings("none", OptimizationMode.development.llvmCodeGenLevelName());
    try std.testing.expectEqualStrings("default", OptimizationMode.release.llvmCodeGenLevelName());
}
