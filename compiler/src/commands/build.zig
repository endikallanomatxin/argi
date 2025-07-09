const std = @import("std");
const fs = std.fs;
const allocator = std.heap.page_allocator;

const llvm = @import("../llvm.zig");
const c = llvm.c;

const codegen = @import("../codegen.zig");
const tok = @import("../tokenizer.zig");
const syn = @import("../syntaxer.zig");
const sem = @import("../semantizer.zig");
const link = @import("../link.zig");

pub fn compile(filename: []const u8) !void {
    std.debug.print("Compilando archivo: {s}\n", .{filename});

    // 1. Leer el archivo fuente.
    var file = try fs.cwd().openFile(filename, .{});
    const source = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    // 2. Lexear el contenido para obtener la lista de tokens.
    var tokenizer = tok.Tokenizer.init(&allocator, source, filename);
    const tokensList = try tokenizer.tokenize();
    tokenizer.printTokens();

    // 3. Parsear la lista de tokens para obtener el ST.
    var syntaxer = syn.Syntaxer.init(&allocator, tokensList);
    const st_nodes = try syntaxer.parse();
    syntaxer.printST();

    // 4. Analizar el st para generar el sg
    var sematizer = sem.Semantizer.init(&allocator, st_nodes);
    const sg = try sematizer.analyze();
    sematizer.printSG();

    // 5. Generar IR a partir del AST.
    var g = codegen.CodeGenerator.init(&allocator, sg) catch return;
    const module = try g.generate();
    const llvm_output_filename = "output.ll";
    var err_msg: [*c]u8 = null;
    if (c.LLVMPrintModuleToFile(module, llvm_output_filename, &err_msg) != 0) {
        std.debug.print("Error al escribir el módulo LLVM: {s}\n", .{err_msg});
        return error.WriteFailed;
    }
    std.debug.print("Código LLVM IR guardado en {s}\n", .{llvm_output_filename});

    // 5. Compilar el IR a un ejecutable usando Clang.
    std.debug.print("\n\nCOMPILATION\n", .{});
    var env = std.process.getEnvMap(allocator) catch return;
    defer env.deinit();

    const triple_cstr = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_cstr);
    const triple = std.mem.span(triple_cstr);

    const out_path = "output"; // binario final
    try link.linkWithLibc(module, triple, out_path, &allocator);
    std.debug.print("✔ Generado {s}\n", .{out_path});
}
