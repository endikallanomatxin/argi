const std = @import("std");
const fs = std.fs;
const allocator = std.heap.page_allocator;

const llvm = @import("../llvm.zig");
const c = llvm.c;
const codegen = @import("../codegen.zig");
const lexer = @import("../lexer.zig");
const parser = @import("../parser.zig");
const type_inference = @import("../type_inference.zig");

pub fn compile(filename: []const u8) !void {
    std.debug.print("Compilando archivo: {s}\n", .{filename});

    // 1. Leer el archivo fuente.
    var file = try fs.cwd().openFile(filename, .{});
    const source = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    // 2. Lexear el contenido para obtener la lista de tokens.
    var l = lexer.Lexer.init(&allocator, source);
    var tokensList = try l.tokenize();
    defer tokensList.deinit();
    l.printTokens();

    // 3. Parsear la lista de tokens para obtener el AST.
    var p = parser.Parser.init(&allocator, tokensList.items);
    const astList = try p.parse();
    defer astList.deinit();
    p.printAST();

    // 4. Inferir tipos en el AST.
    try type_inference.inferTypes(&allocator, astList);

    // 5. Generar IR a partir del AST.
    var g = codegen.CodeGenerator.init(&allocator, astList) catch return;
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
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "clang", llvm_output_filename, "-o", "output" },
    }) catch return;
    _ = result;

    std.debug.print("Compilación completada. Ejecutable generado: ./output\n", .{});
}
