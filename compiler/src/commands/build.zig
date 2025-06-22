const std = @import("std");
const fs = std.fs;
const allocator = std.heap.page_allocator;

const llvm = @import("../llvm.zig");
const c = llvm.c;

const codegen = @import("../codegen.zig");
const tok = @import("../tokenizer.zig");
const syn = @import("../syntaxer.zig");
const sem = @import("../semantizer.zig");

pub fn compile(filename: []const u8) !void {
    std.debug.print("Compilando archivo: {s}\n", .{filename});

    // 1. Leer el archivo fuente.
    var file = try fs.cwd().openFile(filename, .{});
    const source = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    // 2. Lexear el contenido para obtener la lista de tokens.
    var tokenizer = tok.Tokenizer.init(&allocator, source, filename);
    var tokensList = try tokenizer.tokenize();
    defer tokensList.deinit();
    // tokenizer.printTokens();

    // 3. Parsear la lista de tokens para obtener el ST.
    var syntaxer = syn.Syntaxer.init(&allocator, tokensList.items);
    const st_nodes = try syntaxer.parse();
    defer st_nodes.deinit();
    // syntaxer.printST();

    // 4. Analizar el st para generar el sg
    var sematizer = sem.Semantizer.init(&allocator, st_nodes.items);
    const sg = try sematizer.analyze();
    defer sg.deinit();
    // sematizer.printSG();

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

    if (std.process.can_execv) {
        // 5. Compilar el IR a un ejecutable usando Clang.
        std.debug.print("\n\nCOMPILATION\n", .{});
        var env = std.process.getEnvMap(allocator) catch return;
        defer env.deinit();
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "clang", llvm_output_filename, "-o", "output" },
            .env_map = &env,
        }) catch |err| {
            std.debug.print("Error al ejecutar el comando de compilación: {}\n", .{err});
            return err;
        };
        if (result.term.Exited != 0) {
            std.debug.print("El comando de compilación falló con código de salida: {}\n", .{result.term.Exited});
            std.debug.print("STDOUT:\n{s}\n", .{result.stdout});
            std.debug.print("STDERR:\n{s}\n", .{result.stderr});
            return error.CompilationFailed;
        }

        std.debug.print("Compilación completada. Ejecutable generado: ./output\n", .{});
    } else {
        std.debug.print("No se puede ejecutar el comando de compilación, porque no se soporta en este sistema.\n", .{});
        std.debug.print("Ejecute el comando manualmente:\n", .{});
        std.debug.print("  clang {s} -o output\n", .{llvm_output_filename});
        return error.UnsupportedPlatform;
    }
}
