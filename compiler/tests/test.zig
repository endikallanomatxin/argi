const std = @import("std");
const expect = std.testing.expect;
const allocator = std.heap.page_allocator;
// const allocator = std.testing.allocator;

fn clean() !void {
    // Borrar ./output y ./output.ll si existen
    const cwd = std.fs.cwd();
    cwd.deleteFile("output.ll") catch |err| {
        if (err != error.FileNotFound) return err; // Ignorar si no existe
    };
    cwd.deleteFile("output") catch |err| {
        if (err != error.FileNotFound) return err; // Ignorar si no existe
    };
}

fn build(name: []const u8) !void {
    // Ejecutar el comando de compilación
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "./zig-out/bin/argi", "build", name },
    });
}

fn run() !void {
    // Ejecutar el comando de compilación
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{"./output"},
    });
}

test "00_minimal_main" {
    try clean();
    try build("tests/00_minimal_main.rg");
    try run();
}

test "01_comments" {
    try clean();
    try build("tests/01_comments.rg");
    try run();
}

test "02_constants_and_variables" {
    try clean();
    try build("tests/02_constants_and_variables.rg");
    try run();
}

test "03_expressions_and_type_inference" {
    try clean();
    try build("tests/03_expressions_and_type_inference.rg");
    try run();
}

test "04_literals" {
    try clean();
    try build("tests/04_literals.rg");
    try run();
}

test "05_anonymous_structs" {
    try clean();
    try build("tests/05_anonymous_structs.rg");
    try run();
}

test "11_function_calling" {
    try clean();
    try build("tests/11_function_calling.rg");
    try run();
}

test "12_function_args" {
    try clean();
    try build("tests/12_function_args.rg");
    try run();
}

test "21_named_struct_types" {
    try clean();
    try build("tests/21_named_struct_types.rg");
    try run();
}

test "22_pointers" {
    try clean();
    try build("tests/22_pointers.rg");
    try run();
}

test "30_libc" {
    try clean();
    try build("tests/30_libc.rg");
    try run();
}
