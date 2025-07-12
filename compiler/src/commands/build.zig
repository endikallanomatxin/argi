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

pub fn compile(user_path: []const u8) !void {
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
            tokenizer.printTokens();
            diagnostics.dump() catch {};
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
        syntaxer.printST();
        diagnostics.dump() catch {};
        return error.CompilationFailed;
    };

    // 5. Semántica ────────────────────────────────────────────────────────
    var semantizer = sem.Semantizer.init(&allocator, st_nodes, &diagnostics);
    const sg = semantizer.analyze() catch {
        syntaxer.printST();
        semantizer.printSG();
        diagnostics.dump() catch {};
        return error.CompilationFailed;
    };

    // 6. Generación de código ──────────────────────────────────────────────
    var gen = codegen.CodeGenerator.init(&allocator, sg, &diagnostics) catch return;
    const module = gen.generate() catch {
        semantizer.printSG();
        diagnostics.dump() catch {};
        return error.CompilationFailed;
    };

    // 7. Escribir el módulo LLVM a un fichero .ll ──────────────────────
    const ir_path = "output.ll";
    var err_msg: [*c]u8 = null;
    if (c.LLVMPrintModuleToFile(module, ir_path, &err_msg) != 0) {
        std.debug.print("Error al escribir el módulo LLVM: {s}\n", .{err_msg});
        return error.WriteFailed;
    }

    // 8. Enlazar con libc y generar el binario final ──────────────────────
    var env = std.process.getEnvMap(allocator) catch return;
    defer env.deinit();

    const triple_cstr = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_cstr);
    const triple = std.mem.span(triple_cstr);

    try link.linkWithLibc(module, triple, "output", &allocator);
    std.debug.print("✔ Compilación completada\n", .{});
}
