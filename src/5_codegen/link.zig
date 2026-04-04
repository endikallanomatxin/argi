const std = @import("std");
const llvm = @import("llvm.zig");

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
    const c = @import("llvm.zig").c;

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
    const c = @import("llvm.zig").c;
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

    // ─── enlazamos con la libc usando el cc por defecto ───────────────────
    const args_array = [_][]const u8{
        "cc",
        obj_path,
        "-o",
        output_path,
        "-lc",
    };

    // --- convierto ese array en un slice ---
    const argv: []const []const u8 = args_array[0..];
    var child = std.process.Child.init(argv[0..], allocator.*);
    try child.spawn();
    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) return error.LinkFailed;
}
