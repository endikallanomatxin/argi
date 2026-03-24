const std = @import("std");
const llvm = @import("llvm.zig");

const LinkError = error{
    TargetLookupFailed,
    TargetMachineFailed,
    EmitFailedWithMessage,
    LinkFailed,
};

/// Compila el `LLVMModuleRef` que llega de `codegen.generate` a objeto
/// y lo enlaza con la libc del sistema produciendo `output_path`.
pub fn linkWithLibc(
    module: llvm.c.LLVMModuleRef,
    triple: []const u8,
    output_path: []const u8,
    allocator: *const std.mem.Allocator,
) !void {
    const c = @import("llvm.zig").c;

    // ─── inicializar back-end nativo ───────────────────────────────────────
    if (c.LLVMInitializeNativeTarget() != 0 or c.LLVMInitializeNativeAsmPrinter() != 0)
        return error.LLVMTargetInitFailed;

    // ─── crear TargetMachine ───────────────────────────────────────────────
    var err_ptr: [*c]u8 = null;
    // LLVM devuelve el target por referencia:
    var target_ref: llvm.c.LLVMTargetRef = null;

    if (c.LLVMGetTargetFromTriple(triple.ptr, &target_ref, &err_ptr) != 0) {
        std.debug.print("LLVMGetTargetFromTriple failed: {s}\n", .{err_ptr});
        c.LLVMDisposeMessage(err_ptr);
        return LinkError.TargetLookupFailed;
    }

    const target = target_ref;
    defer if (err_ptr) |p| c.LLVMDisposeMessage(p);

    const tm = c.LLVMCreateTargetMachine(
        target,
        triple.ptr,
        "", // CPU
        "", // features
        c.LLVMCodeGenLevelDefault,
        c.LLVMRelocPIC,
        c.LLVMCodeModelDefault,
    ) orelse return error.TargetMachineFailed;
    defer c.LLVMDisposeTargetMachine(tm);

    c.LLVMSetTarget(module, triple.ptr);

    // ─── volcar a objeto intermedio ────────────────────────────────────────
    var obj_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const obj_path =
        (try std.fmt.bufPrintZ(&obj_path_buf, "{s}.o", .{output_path})).ptr;
    err_ptr = null;

    if (c.LLVMTargetMachineEmitToFile(
        tm,
        module,
        @ptrCast(obj_path),
        c.LLVMObjectFile,
        &err_ptr,
    ) != 0) {
        // const msg = std.mem.span(err_ptr);
        return error.EmitFailedWithMessage; // pásala hacia arriba
    }

    // ─── enlazamos con la libc usando el cc por defecto ───────────────────
    const args_array = [_][]const u8{
        "cc",
        std.mem.span(obj_path),
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
