const std = @import("std");
const fs = std.fs;

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
};

fn parseFlags(args: []const []const u8) BuildFlags {
    var flags: BuildFlags = .{};
    for (args) |a| {
        if (std.mem.eql(u8, a, "--on-build-error-show-cascade")) flags.show_cascade = true
            //
        else if (std.mem.eql(u8, a, "--on-build-error-show-syntax-tree")) flags.show_syntax_tree = true
            //
        else if (std.mem.eql(u8, a, "--on-build-error-show-semantic-graph")) flags.show_semantic_graph = true
            //
        else if (std.mem.eql(u8, a, "--on-build-error-show-token-list")) flags.show_token_list = true;
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

fn resolveBuildModuleDir(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
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

pub fn compile(args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const target_path = args[0];
    const flags = parseFlags(args[1..]);
    const module_dir = try resolveBuildModuleDir(allocator, target_path);
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

        // Elimina el EOF salvo en el último fichero
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

    const temp_stem = try std.fmt.allocPrint(allocator, "output.tmp.{d}", .{std.time.nanoTimestamp()});
    const temp_ir_path = try std.fmt.allocPrint(allocator, "{s}.ll", .{temp_stem});
    const final_ir_path = "output.ll";
    const final_output_path = "output";

    std.fs.cwd().deleteFile(temp_ir_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    std.fs.cwd().deleteFile(temp_stem) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    std.fs.cwd().deleteFile("output.o") catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // 8. Escribir el módulo LLVM a un fichero .ll ──────────────────────
    var err_msg: [*c]u8 = null;
    const temp_ir_path_c = try allocator.dupeZ(u8, temp_ir_path);
    if (c.LLVMPrintModuleToFile(module, temp_ir_path_c.ptr, &err_msg) != 0) {
        std.debug.print("Failed to write LLVM module: {s}\n", .{err_msg});
        return error.WriteFailed;
    }

    // 9. Enlazar con libc y generar el binario final ──────────────────────
    const triple_cstr = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_cstr);
    const triple = std.mem.span(triple_cstr);

    try link.linkWithLibc(module, triple, temp_stem, &allocator);

    std.fs.cwd().deleteFile(final_ir_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    if (std.fs.cwd().statFile(temp_ir_path)) |_| {} else |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing temp ir before rename: {s}\n", .{temp_ir_path});
            return err;
        },
        else => return err,
    }
    std.fs.cwd().rename(temp_ir_path, final_ir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.cwd().deleteFile(final_ir_path);
            try std.fs.cwd().rename(temp_ir_path, final_ir_path);
        },
        else => return err,
    };

    std.fs.cwd().deleteFile(final_output_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    if (std.fs.cwd().statFile(temp_stem)) |_| {} else |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing temp output before rename: {s}\n", .{temp_stem});
            return err;
        },
        else => return err,
    }
    std.fs.cwd().rename(temp_stem, final_output_path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.cwd().deleteFile(final_output_path);
            try std.fs.cwd().rename(temp_stem, final_output_path);
        },
        else => return err,
    };

    var temp_obj_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_obj_path = try std.fmt.bufPrint(&temp_obj_path_buf, "{s}.o", .{temp_stem});
    if (std.fs.cwd().statFile(temp_obj_path)) |_| {} else |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("missing temp obj before rename: {s}\n", .{temp_obj_path});
            return err;
        },
        else => return err,
    }

    std.fs.cwd().rename(temp_obj_path, "output.o") catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.cwd().deleteFile("output.o");
            try std.fs.cwd().rename(temp_obj_path, "output.o");
        },
        else => return err,
    };

    std.debug.print("✔ Build completed\n", .{});
}
