const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;

const LinkError = error{
    TargetLookupFailed,
    TargetMachineFailed,
    EmitFailedWithMessage,
    LinkFailed,
};

fn createTargetMachine(
    module: llvm.c.LLVMModuleRef,
    triple: []const u8,
) !llvm.c.LLVMTargetMachineRef {
    if (c.LLVMInitializeNativeTarget() != 0 or c.LLVMInitializeNativeAsmPrinter() != 0)
        return error.LLVMTargetInitFailed;

    var err_ptr: [*c]u8 = null;
    var target_ref: llvm.c.LLVMTargetRef = null;

    if (c.LLVMGetTargetFromTriple(triple.ptr, &target_ref, &err_ptr) != 0) {
        std.debug.print("LLVMGetTargetFromTriple failed: {s}\n", .{err_ptr});
        c.LLVMDisposeMessage(err_ptr);
        return LinkError.TargetLookupFailed;
    }

    defer if (err_ptr) |p| c.LLVMDisposeMessage(p);

    const tm = c.LLVMCreateTargetMachine(
        target_ref,
        triple.ptr,
        "", // CPU
        "", // features
        c.LLVMCodeGenLevelDefault,
        c.LLVMRelocPIC,
        c.LLVMCodeModelDefault,
    ) orelse return error.TargetMachineFailed;

    c.LLVMSetTarget(module, triple.ptr);
    return tm;
}

pub fn emitObjectFile(
    module: llvm.c.LLVMModuleRef,
    triple: []const u8,
    obj_output_path: []const u8,
) !void {
    const tm = try createTargetMachine(module, triple);
    defer c.LLVMDisposeTargetMachine(tm);

    var err_ptr: [*c]u8 = null;
    const obj_path_z = try std.heap.c_allocator.dupeZ(u8, obj_output_path);
    defer std.heap.c_allocator.free(obj_path_z);
    if (c.LLVMTargetMachineEmitToFile(
        tm,
        module,
        @ptrCast(obj_path_z.ptr),
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

fn buildLinkArgv(
    linker: []const u8,
    obj_path: []const u8,
    output_path: []const u8,
) [5][]const u8 {
    // For 0.1 we link against the platform C runtime explicitly.
    // This keeps the current backend simple and will be revisited later.
    return .{ linker, obj_path, "-o", output_path, "-lc" };
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
        .Exited => |code| std.debug.print("linker exited with code {d}\n", .{code}),
        .Signal => |signal| std.debug.print("linker terminated by signal {d}\n", .{signal}),
        .Stopped => |signal| std.debug.print("linker stopped by signal {d}\n", .{signal}),
        .Unknown => |code| std.debug.print("linker terminated unexpectedly ({d})\n", .{code}),
    }
}

fn printLinkerFailure(
    linker: []const u8,
    argv: []const []const u8,
    result: ?std.process.Child.RunResult,
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

/// Compila el `LLVMModuleRef` que llega de `codegen.generate` a objeto
/// y lo enlaza con la libc del sistema produciendo `output_path`.
pub fn linkWithLibc(
    module: llvm.c.LLVMModuleRef,
    triple: []const u8,
    output_path: []const u8,
    allocator: *const std.mem.Allocator,
) !void {
    var obj_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const obj_path = try std.fmt.bufPrint(&obj_path_buf, "{s}.o", .{output_path});
    try emitObjectFile(module, triple, obj_path);

    const cc_env = std.process.getEnvVarOwned(allocator.*, "CC") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (cc_env) |value| allocator.free(value);
    const linker = chooseLinkerCommand(cc_env);

    const argv_array = buildLinkArgv(linker, obj_path, output_path);
    const argv = argv_array[0..];

    const result = std.process.Child.run(.{
        .allocator = allocator.*,
        .argv = argv,
    }) catch |err| {
        printLinkerFailure(linker, argv, null, err);
        return error.LinkFailed;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
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
    const argv = buildLinkArgv("clang", "/tmp/input.o", "/tmp/output");
    try std.testing.expectEqualStrings("clang", argv[0]);
    try std.testing.expectEqualStrings("/tmp/input.o", argv[1]);
    try std.testing.expectEqualStrings("-o", argv[2]);
    try std.testing.expectEqualStrings("/tmp/output", argv[3]);
    try std.testing.expectEqualStrings("-lc", argv[4]);
}
