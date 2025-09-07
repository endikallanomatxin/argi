const std = @import("std");
const fs = std.fs;
const allocator = std.heap.page_allocator;

const llvm = @import("../llvm.zig");
const c = llvm.c;

const sf = @import("../source_files.zig");
const diag = @import("../diagnostic.zig");
const token = @import("../token.zig");
const tokzr = @import("../tokenizer.zig");
const syn = @import("../syntaxer.zig");
const sem = @import("../semantizer.zig");
const link = @import("../link.zig");
const codegen = @import("../codegen.zig");
const tokp = @import("../token_print.zig");

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
        else if (std.mem.eql(u8, a, "--on-build-error-show-syntax-tree")) flags.show_syntax_tree = true
        else if (std.mem.eql(u8, a, "--on-build-error-show-semantic-graph")) flags.show_semantic_graph = true
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

pub fn compile(args: []const []const u8) !void {
    const user_path = args[0];
    const flags = parseFlags(args[1..]);
    // 1. Reunir ficheros ──────────────────────────────────────────────────
    var files = try sf.collect(&allocator, "core", user_path);
    defer sf.freeList(&allocator, &files);

    // 2. Diagnósticos globales ────────────────────────────────────────────
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();

    // 3. Tokenizar todos (fusionando EOF) ─────────────────────────────────
    var all_tokens = std.ArrayList(token.Token).init(allocator);
    defer all_tokens.deinit();

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

    // 8. Escribir el módulo LLVM a un fichero .ll ──────────────────────
    const ir_path = "output.ll";
    var err_msg: [*c]u8 = null;
    if (c.LLVMPrintModuleToFile(module, ir_path, &err_msg) != 0) {
        std.debug.print("Failed to write LLVM module: {s}\n", .{err_msg});
        return error.WriteFailed;
    }

    // 9. Enlazar con libc y generar el binario final ──────────────────────
    var env = std.process.getEnvMap(allocator) catch return;
    defer env.deinit();

    const triple_cstr = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_cstr);
    const triple = std.mem.span(triple_cstr);

    try link.linkWithLibc(module, triple, "output", &allocator);
    std.debug.print("✔ Build completed\n", .{});
}
