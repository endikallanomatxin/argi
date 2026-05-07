const std = @import("std");
const argi_version = @import("version.zig");

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
    const package_name = try packageNameFromPath(allocator, root_path, "module");
    defer allocator.free(package_name);

    const readme_path = try std.fs.path.join(allocator, &.{ root_path, "README.md" });
    defer allocator.free(readme_path);
    const readme = try moduleReadmeTemplate(allocator, package_name);
    defer allocator.free(readme);
    try writeFileIfMissing(readme_path, readme);

    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "argi.toml" });
    defer allocator.free(manifest_path);
    const manifest = try manifestTemplate(allocator, package_name, "module");
    defer allocator.free(manifest);
    try writeFileIfMissing(manifest_path, manifest);

    const gitignore_path = try std.fs.path.join(allocator, &.{ root_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try writeFileIfMissing(gitignore_path, gitignoreTemplate);
}

fn initProject(allocator: std.mem.Allocator, root_path: []const u8) !void {
    try std.fs.cwd().makePath(root_path);
    const package_name = try packageNameFromPath(allocator, root_path, "project");
    defer allocator.free(package_name);

    const entry_dir = try std.fs.path.join(allocator, &.{ root_path, "source", "entrypoints", "main" });
    defer allocator.free(entry_dir);
    try std.fs.cwd().makePath(entry_dir);

    const readme_path = try std.fs.path.join(allocator, &.{ root_path, "README.md" });
    defer allocator.free(readme_path);
    const readme = try projectReadmeTemplate(allocator, package_name);
    defer allocator.free(readme);
    try writeFileIfMissing(readme_path, readme);

    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "argi.toml" });
    defer allocator.free(manifest_path);
    const manifest = try manifestTemplate(allocator, package_name, "project");
    defer allocator.free(manifest);
    try writeFileIfMissing(manifest_path, manifest);

    const entry_main_path = try std.fs.path.join(allocator, &.{ root_path, "source", "entrypoints", "main", "main.rg" });
    defer allocator.free(entry_main_path);
    try writeFileIfMissing(entry_main_path, moduleMainTemplate);

    const gitignore_path = try std.fs.path.join(allocator, &.{ root_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try writeFileIfMissing(gitignore_path, gitignoreTemplate);
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

const gitignoreTemplate =
    \\.argi-cache/
    \\build/
    \\**/build/
    \\
;

fn packageNameFromPath(allocator: std.mem.Allocator, root_path: []const u8, fallback: []const u8) ![]u8 {
    const base = std.fs.path.basename(root_path);
    var out = std.array_list.Managed(u8).init(allocator);
    defer out.deinit();

    for (base) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_') {
            try out.append(std.ascii.toLower(ch));
        } else if (ch == ' ' or ch == '.') {
            try out.append('-');
        }
    }

    if (out.items.len == 0) try out.appendSlice(fallback);
    return try out.toOwnedSlice();
}

fn manifestTemplate(allocator: std.mem.Allocator, package_name: []const u8, kind: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\name = "{s}"
        \\version = "0.0.0"
        \\kind = "{s}"
        \\minimum_argi_version = "{s}"
        \\
        ,
        .{ package_name, kind, argi_version.current },
    );
}

fn moduleReadmeTemplate(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\# {s}
        \\
        \\Argi module package.
        \\
        \\This package is a folder module intended to be imported by another
        \\Argi module. Add `.rg` files when the package needs public API.
        \\
        ,
        .{package_name},
    );
}

fn projectReadmeTemplate(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\# {s}
        \\
        \\Argi project package.
        \\
        \\Build the default entrypoint with:
        \\
        \\```sh
        \\argi build source/entrypoints/main
        \\```
        \\
        \\Run it with:
        \\
        \\```sh
        \\argi run source/entrypoints/main
        \\```
        \\
        ,
        .{package_name},
    );
}

fn expectFileExists(path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    file.close();
}

fn expectFileMissing(path: []const u8) !void {
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    return error.UnexpectedFile;
}

fn expectFileContains(path: []const u8, expected: []const u8) !void {
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, path, 1024 * 1024);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, expected) != null);
}

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
    const manifest = try std.fs.path.join(std.testing.allocator, &.{ module_root, "argi.toml" });
    defer std.testing.allocator.free(manifest);
    const gitignore = try std.fs.path.join(std.testing.allocator, &.{ module_root, ".gitignore" });
    defer std.testing.allocator.free(gitignore);
    const main_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "main.rg" });
    defer std.testing.allocator.free(main_path);

    try expectFileExists(readme);
    try expectFileExists(manifest);
    try expectFileExists(gitignore);
    try expectFileMissing(main_path);
    try expectFileContains(manifest, "version = \"0.0.0\"\n");
    try expectFileContains(manifest, "minimum_argi_version = \"0.1.0\"\n");
}

test "init project scaffolds basic layout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_root);
    const project_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "sample_project" });
    defer std.testing.allocator.free(project_root);

    try initAtPath(std.testing.allocator, .project, project_root);

    const entry_main = try std.fs.path.join(std.testing.allocator, &.{ project_root, "source", "entrypoints", "main", "main.rg" });
    defer std.testing.allocator.free(entry_main);
    const manifest = try std.fs.path.join(std.testing.allocator, &.{ project_root, "argi.toml" });
    defer std.testing.allocator.free(manifest);
    const gitignore = try std.fs.path.join(std.testing.allocator, &.{ project_root, ".gitignore" });
    defer std.testing.allocator.free(gitignore);
    const public_dir = try std.fs.path.join(std.testing.allocator, &.{ project_root, "public" });
    defer std.testing.allocator.free(public_dir);
    const private_dir = try std.fs.path.join(std.testing.allocator, &.{ project_root, "private" });
    defer std.testing.allocator.free(private_dir);

    try expectFileExists(entry_main);
    try expectFileExists(manifest);
    try expectFileExists(gitignore);
    try expectFileMissing(public_dir);
    try expectFileMissing(private_dir);
    try expectFileContains(manifest, "version = \"0.0.0\"\n");
    try expectFileContains(manifest, "minimum_argi_version = \"0.1.0\"\n");
}
