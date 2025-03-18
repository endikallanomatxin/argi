const std = @import("std");
const fs = std.fs;
const allocator = std.heap.page_allocator;

const llvm = @import("../llvm.zig");
const c = llvm.c;
const codegen = @import("../codegen.zig");
const lexer = @import("../lexer.zig");
const parser = @import("../parser.zig");

pub fn compile(filename: []const u8) !void {
    std.debug.print("Compilando archivo: {s}\n", .{filename});

    // 1. Leer el archivo fuente.
    var file = try fs.cwd().openFile(filename, .{});
    const source = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    // 2. Lexear el contenido para obtener la lista de tokens.
    var tokensList = try lexer.tokenize(allocator, source);
    defer tokensList.deinit();
    lexer.printTokenList(tokensList.items, 4);

    // 3. Parsear la lista de tokens para obtener el AST.
    var p = parser.initParser(tokensList.items);
    const astList = try parser.parse(&p, &allocator);
    defer astList.deinit();
    parser.printAST(astList.items);
    // Nota: astList es, por ejemplo, una ArrayList(ASTNode) que contiene
    // la declaración de la función 'main' y sus sentencias.
    // Aquí podrías imprimir el AST para depuración.

    // 4. Generar IR a partir del AST.
    // Para este ejemplo, suponemos que has definido en codegen.zig
    // una función generateIRFromAST que recibe el AST y devuelve un LLVMModuleRef.
    // Si aún no la has implementado, temporalmente puedes usar generateIR(filename)
    // y luego migrar a la versión basada en AST.
    const llvm_filename = "output.ll";
    const module = try codegen.generateIR(astList, llvm_filename);

    // 5. Guardar el LLVM IR en un archivo.
    const output_filename = "output.ll";
    var err_msg: [*c]u8 = null;
    if (c.LLVMPrintModuleToFile(module, output_filename, &err_msg) != 0) {
        std.debug.print("Error al escribir el módulo LLVM: {s}\n", .{err_msg});
        return error.WriteFailed;
    }
    std.debug.print("Código LLVM IR guardado en {s}\n", .{output_filename});

    // 6. Compilar el IR a un ejecutable usando Clang.
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "clang", output_filename, "-o", "output" },
    }) catch return;
    _ = result;

    std.debug.print("Compilación completada. Ejecutable generado: ./output\n", .{});
}
