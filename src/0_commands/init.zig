const std = @import("std");

pub const InitKind = enum {
    project,
    module,
};

pub fn run(args: []const []const u8) !void {
    if (args.len < 2) return error.InvalidArguments;

    const kind = parseKind(args[0]) orelse return error.InvalidArguments;
    try initAtPath(std.heap.page_allocator, kind, args[1]);
}

pub fn initAtPath(allocator: std.mem.Allocator, kind: InitKind, root_path: []const u8) !void {
    switch (kind) {
        .module => try initModule(allocator, root_path),
        .project => try initProject(allocator, root_path),
    }
}

fn parseKind(text: []const u8) ?InitKind {
    if (std.mem.eql(u8, text, "project")) return .project;
    if (std.mem.eql(u8, text, "module")) return .module;
    return null;
}

fn initModule(allocator: std.mem.Allocator, root_path: []const u8) !void {
    try std.fs.cwd().makePath(root_path);

    const readme_path = try std.fs.path.join(allocator, &.{ root_path, "README.md" });
    defer allocator.free(readme_path);
    try writeFileIfMissing(readme_path, "# Module\n");

    const main_path = try std.fs.path.join(allocator, &.{ root_path, "main.rg" });
    defer allocator.free(main_path);
    try writeFileIfMissing(main_path, moduleMainTemplate);
}

fn initProject(allocator: std.mem.Allocator, root_path: []const u8) !void {
    try std.fs.cwd().makePath(root_path);

    const entry_dir = try std.fs.path.join(allocator, &.{ root_path, "entrypoints", "main" });
    defer allocator.free(entry_dir);
    try std.fs.cwd().makePath(entry_dir);

    const public_dir = try std.fs.path.join(allocator, &.{ root_path, "public" });
    defer allocator.free(public_dir);
    try std.fs.cwd().makePath(public_dir);

    const private_dir = try std.fs.path.join(allocator, &.{ root_path, "private" });
    defer allocator.free(private_dir);
    try std.fs.cwd().makePath(private_dir);

    const results_dir = try std.fs.path.join(allocator, &.{ root_path, "results" });
    defer allocator.free(results_dir);
    try std.fs.cwd().makePath(results_dir);

    const readme_path = try std.fs.path.join(allocator, &.{ root_path, "README.md" });
    defer allocator.free(readme_path);
    try writeFileIfMissing(readme_path, "# Project\n");

    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "project.rgstruct" });
    defer allocator.free(manifest_path);
    try writeFileIfMissing(manifest_path, projectManifestTemplate);

    const entry_main_path = try std.fs.path.join(allocator, &.{ root_path, "entrypoints", "main", "main.rg" });
    defer allocator.free(entry_main_path);
    try writeFileIfMissing(entry_main_path, moduleMainTemplate);

    const gitignore_path = try std.fs.path.join(allocator, &.{ root_path, "results", ".gitignore" });
    defer allocator.free(gitignore_path);
    try writeFileIfMissing(gitignore_path, "*\n");
}

fn writeFileIfMissing(path: []const u8, contents: []const u8) !void {
    const file = std.fs.cwd().createFile(path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close();
    try file.writeAll(contents);
}

const moduleMainTemplate =
    \\main() -> (.status_code: Int32 = 0) := {
    \\}
    \\
;

const projectManifestTemplate =
    \\(
    \\)
    \\
;

test "init module scaffolds minimal files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "sample_module" });
    defer std.testing.allocator.free(module_root);

    try initAtPath(std.testing.allocator, .module, module_root);

    const readme = try std.fs.path.join(std.testing.allocator, &.{ module_root, "README.md" });
    defer std.testing.allocator.free(readme);
    const main_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "main.rg" });
    defer std.testing.allocator.free(main_path);

    _ = try std.fs.cwd().openFile(readme, .{});
    _ = try std.fs.cwd().openFile(main_path, .{});
}

test "init project scaffolds basic layout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const project_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "sample_project" });
    defer std.testing.allocator.free(project_root);

    try initAtPath(std.testing.allocator, .project, project_root);

    const entry_main = try std.fs.path.join(std.testing.allocator, &.{ project_root, "entrypoints", "main", "main.rg" });
    defer std.testing.allocator.free(entry_main);
    const manifest = try std.fs.path.join(std.testing.allocator, &.{ project_root, "project.rgstruct" });
    defer std.testing.allocator.free(manifest);
    const gitignore = try std.fs.path.join(std.testing.allocator, &.{ project_root, "results", ".gitignore" });
    defer std.testing.allocator.free(gitignore);

    _ = try std.fs.cwd().openFile(entry_main, .{});
    _ = try std.fs.cwd().openFile(manifest, .{});
    _ = try std.fs.cwd().openFile(gitignore, .{});
}
