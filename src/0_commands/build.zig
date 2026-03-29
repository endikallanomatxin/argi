const std = @import("std");

const llvm = @import("../5_codegen/llvm.zig");
const c = llvm.c;

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokzr = @import("../2_tokens/tokenizer.zig");
const syn = @import("../3_syntax/syntaxer.zig");
const sem = @import("../4_semantics/semantizer.zig");
const link = @import("../5_codegen/link.zig");
const codegen = @import("../5_codegen/codegen.zig");
const tokp = @import("../2_tokens/token_print.zig");

const BuildFlags = struct {
    show_cascade: bool = false,
    show_syntax_tree: bool = false,
    show_semantic_graph: bool = false,
    show_token_list: bool = false,
    output_path: ?[]const u8 = null,
    llvm_ir_path: ?[]const u8 = null,
    object_path: ?[]const u8 = null,
};

fn parseFlags(args: []const []const u8) !BuildFlags {
    var flags: BuildFlags = .{};
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const a = args[idx];
        if (std.mem.eql(u8, a, "--on-build-error-show-cascade")) {
            flags.show_cascade = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-syntax-tree")) {
            flags.show_syntax_tree = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-semantic-graph")) {
            flags.show_semantic_graph = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-token-list")) {
            flags.show_token_list = true;
        } else if (std.mem.eql(u8, a, "--output")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.output_path = args[idx];
        } else if (std.mem.eql(u8, a, "--emit-llvm")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.llvm_ir_path = args[idx];
        } else if (std.mem.eql(u8, a, "--emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.object_path = args[idx];
        }
    }
    return flags;
}

fn printTokenList(all: []const token.Token) void {
    std.debug.print("\nTOKENS\n", .{});
    for (all, 0..) |t, i| {
        std.debug.print("{d}: ", .{i});
        tokp.printTokenWithLocation(t, t.location);
    }
}

pub fn resolveBuildModuleDir(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.cwd().openDir(path, .{})) |opened_dir| {
        var dir = opened_dir;
        dir.close();
        return std.fs.path.resolve(allocator, &.{path});
    } else |dir_err| switch (dir_err) {
        error.NotDir, error.FileNotFound => {},
        else => return dir_err,
    }

    _ = try std.fs.cwd().statFile(path);
    const dir = std.fs.path.dirname(path) orelse ".";
    return std.fs.path.resolve(allocator, &.{dir});
}

fn ensureParentDir(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0 or std.mem.eql(u8, parent, ".")) return;
    try std.fs.cwd().makePath(parent);
}

pub fn defaultOutputPathForModuleDir(allocator: std.mem.Allocator, module_dir: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/build/output",
        .{module_dir},
    );
}

fn replaceFile(src: []const u8, dst: []const u8) !void {
    std.fs.cwd().rename(src, dst) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.cwd().deleteFile(dst);
            try std.fs.cwd().rename(src, dst);
        },
        else => return err,
    };
}

pub fn compile(args: []const []const u8) !void {
    if (args.len == 0) return error.MissingBuildTarget;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const target_path = args[0];
    const flags = try parseFlags(args[1..]);
    const module_dir = try resolveBuildModuleDir(allocator, target_path);

    // Salidas finales por defecto dentro del módulo compilado.
    const final_output_path = if (flags.output_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else
        try defaultOutputPathForModuleDir(allocator, module_dir);
    const final_ir_path = if (flags.llvm_ir_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else
        try std.fmt.allocPrint(allocator, "{s}.ll", .{final_output_path});
    const final_obj_path = if (flags.object_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else
        try std.fmt.allocPrint(allocator, "{s}.o", .{final_output_path});

    try ensureParentDir(final_output_path);
    try ensureParentDir(final_ir_path);
    try ensureParentDir(final_obj_path);

    // 1. Reunir ficheros ──────────────────────────────────────────────────
    const files = try sf.collectModule(&allocator, "core", module_dir);

    // 2. Diagnósticos globales ────────────────────────────────────────────
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);

    // 3. Tokenizar todos (fusionando EOF) ─────────────────────────────────
    var all_tokens = std.array_list.Managed(token.Token).init(allocator);

    for (files.items, 0..) |f, idx| {
        var tokenizer = tokzr.Tokenizer.init(
            &allocator,
            &diagnostics,
            f.code,
            f.path,
        );
        const toks = tokenizer.tokenize() catch {
            if (flags.show_token_list) tokenizer.printTokens();
            diagnostics.dumpWithLimit(if (flags.show_cascade) std.math.maxInt(usize) else 1) catch {};
            return error.CompilationFailed;
        };

        const slice = if (idx == files.items.len - 1)
            toks
        else
            toks[0 .. toks.len - 1];

        try all_tokens.appendSlice(slice);
    }

    // 4. Sintaxis ──────────────────────────────────────────────────────────
    var syntaxer = syn.Syntaxer.init(&allocator, all_tokens.items, &diagnostics);
    const st_nodes = syntaxer.parse() catch {
        if (flags.show_token_list) printTokenList(all_tokens.items);
        if (flags.show_syntax_tree) syntaxer.printST();
        diagnostics.dumpWithLimit(if (flags.show_cascade) std.math.maxInt(usize) else 1) catch {};
        return error.CompilationFailed;
    };

    // 5. Semántica ────────────────────────────────────────────────────────
    var semantizer = sem.Semantizer.init(&allocator, st_nodes, &diagnostics);
    const sg = semantizer.analyze() catch {
        if (flags.show_token_list) printTokenList(all_tokens.items);
        if (flags.show_syntax_tree) syntaxer.printST();
        if (flags.show_semantic_graph) semantizer.printSG();
        diagnostics.dumpWithLimit(if (flags.show_cascade) std.math.maxInt(usize) else 1) catch {};
        return error.CompilationFailed;
    };

    // 6. Si hubo errores semánticos, parar antes de codegen ───────────────
    if (diagnostics.hasErrors()) {
        if (flags.show_token_list) printTokenList(all_tokens.items);
        if (flags.show_syntax_tree) syntaxer.printST();
        if (flags.show_semantic_graph) semantizer.printSG();
        diagnostics.dumpWithLimit(if (flags.show_cascade) std.math.maxInt(usize) else 1) catch {};
        return error.CompilationFailed;
    }

    // 7. Generación de código ──────────────────────────────────────────────
    var gen = codegen.CodeGenerator.init(&allocator, sg, &diagnostics) catch return;
    const module = gen.generate() catch {
        if (flags.show_token_list) printTokenList(all_tokens.items);
        if (flags.show_semantic_graph) semantizer.printSG();
        diagnostics.dumpWithLimit(if (flags.show_cascade) std.math.maxInt(usize) else 1) catch {};
        return error.CompilationFailed;
    };

    // Temporales en el mismo directorio final.
    const temp_stem = try std.fmt.allocPrint(
        allocator,
        "{s}.tmp.{d}",
        .{ final_output_path, std.time.nanoTimestamp() },
    );
    const temp_ir_path = try std.fmt.allocPrint(
        allocator,
        "{s}.ll",
        .{temp_stem},
    );
    const temp_obj_path = try std.fmt.allocPrint(
        allocator,
        "{s}.o",
        .{temp_stem},
    );

    try ensureParentDir(temp_stem);
    try ensureParentDir(temp_ir_path);
    try ensureParentDir(temp_obj_path);

    std.fs.cwd().deleteFile(temp_ir_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    std.fs.cwd().deleteFile(temp_stem) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    std.fs.cwd().deleteFile(temp_obj_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // 8. Escribir el módulo LLVM a un fichero .ll ─────────────────────────
    var err_msg: [*c]u8 = null;
    const temp_ir_path_c = try allocator.dupeZ(u8, temp_ir_path);
    if (c.LLVMPrintModuleToFile(module, temp_ir_path_c.ptr, &err_msg) != 0) {
        std.debug.print("Failed to write LLVM module: {s}\n", .{err_msg});
        return error.WriteFailed;
    }

    // 9. Enlazar con libc y generar el binario temporal ───────────────────
    const triple_cstr = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_cstr);
    const triple = std.mem.span(triple_cstr);

    try link.linkWithLibc(module, triple, temp_stem, &allocator);

    // 10. Mover a nombres finales ─────────────────────────────────────────
    if (std.fs.cwd().statFile(temp_ir_path)) |_| {} else |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing temp ir before rename: {s}\n", .{temp_ir_path});
            return err;
        },
        else => return err,
    }
    try replaceFile(temp_ir_path, final_ir_path);

    if (std.fs.cwd().statFile(temp_stem)) |_| {} else |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing temp output before rename: {s}\n", .{temp_stem});
            return err;
        },
        else => return err,
    }
    try replaceFile(temp_stem, final_output_path);

    if (std.fs.cwd().statFile(temp_obj_path)) |_| {} else |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing temp obj before rename: {s}\n", .{temp_obj_path});
            return err;
        },
        else => return err,
    }
    try replaceFile(temp_obj_path, final_obj_path);

    std.debug.print("✔ Build completed\n", .{});
}

test "parse build flags keeps diagnostics toggles and output paths" {
    const flags = try parseFlags(&.{
        "--on-build-error-show-cascade",
        "--on-build-error-show-token-list",
        "--output",
        "bin/app",
        "--emit-llvm",
        "ir/app.ll",
        "--emit-obj",
        "obj/app.o",
    });

    try std.testing.expect(flags.show_cascade);
    try std.testing.expect(flags.show_token_list);
    try std.testing.expectEqualStrings("bin/app", flags.output_path.?);
    try std.testing.expectEqualStrings("ir/app.ll", flags.llvm_ir_path.?);
    try std.testing.expectEqualStrings("obj/app.o", flags.object_path.?);
}

test "parse build flags rejects missing path value" {
    try std.testing.expectError(error.MissingFlagValue, parseFlags(&.{"--output"}));
}
