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
        .argv = &[_][]const u8{ "zig", "build", "run", "--", "build", name },
    });
}

fn run() !void {
    // Ejecutar el comando de compilación
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{"./output"},
    });
}

test "just_build" {
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build" },
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

test "06_function_calling" {
    try clean();
    try build("tests/06_function_calling.rg");
    try run();
}

test "07_function_args.rg" {
    try clean();
    try build("tests/07_function_args.rg");
    try run();
}

test "08_if.rg" {
    try clean();
    try build("tests/08_if.rg");
    try run();
}
