const std = @import("std");
const argi_version = @import("version.zig");

pub const InitKind = enum {
    project,
    module,
};

pub fn run(io: std.Io, args: []const []const u8) !void {
    if (args.len < 2) return error.InvalidArguments;

    const kind = parseKind(args[0]) orelse return error.InvalidArguments;
    try initAtPath(std.heap.page_allocator, io, kind, args[1]);
}

pub fn initAtPath(allocator: std.mem.Allocator, io: std.Io, kind: InitKind, root_path: []const u8) !void {
    switch (kind) {
        .module => try initModule(allocator, io, root_path),
        .project => try initProject(allocator, io, root_path),
    }
}

fn parseKind(text: []const u8) ?InitKind {
    if (std.mem.eql(u8, text, "project")) return .project;
    if (std.mem.eql(u8, text, "module")) return .module;
    return null;
}

fn initModule(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, root_path);
    const package_name = try packageNameFromPath(allocator, root_path, "module");
    defer allocator.free(package_name);

    const readme_path = try std.fs.path.join(allocator, &.{ root_path, "README.md" });
    defer allocator.free(readme_path);
    const readme = try moduleReadmeTemplate(allocator, package_name);
    defer allocator.free(readme);
    try writeFileIfMissing(io, readme_path, readme);

    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "argi.toml" });
    defer allocator.free(manifest_path);
    const manifest = try moduleManifestTemplate(allocator, package_name);
    defer allocator.free(manifest);
    try writeFileIfMissing(io, manifest_path, manifest);

    const gitignore_path = try std.fs.path.join(allocator, &.{ root_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try writeFileIfMissing(io, gitignore_path, gitignoreTemplate);
}

fn initProject(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, root_path);
    const package_name = try packageNameFromPath(allocator, root_path, "project");
    defer allocator.free(package_name);

    const entry_dir = try std.fs.path.join(allocator, &.{ root_path, "source", "entrypoints", "main" });
    defer allocator.free(entry_dir);
    try std.Io.Dir.cwd().createDirPath(io, entry_dir);

    const readme_path = try std.fs.path.join(allocator, &.{ root_path, "README.md" });
    defer allocator.free(readme_path);
    const readme = try projectReadmeTemplate(allocator, package_name);
    defer allocator.free(readme);
    try writeFileIfMissing(io, readme_path, readme);

    const manifest_path = try std.fs.path.join(allocator, &.{ root_path, "argi.toml" });
    defer allocator.free(manifest_path);
    const manifest = try projectManifestTemplate(allocator, package_name);
    defer allocator.free(manifest);
    try writeFileIfMissing(io, manifest_path, manifest);

    const entry_main_path = try std.fs.path.join(allocator, &.{ root_path, "source", "entrypoints", "main", "main.rg" });
    defer allocator.free(entry_main_path);
    try writeFileIfMissing(io, entry_main_path, moduleMainTemplate);

    const gitignore_path = try std.fs.path.join(allocator, &.{ root_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try writeFileIfMissing(io, gitignore_path, gitignoreTemplate);
}

fn writeFileIfMissing(io: std.Io, path: []const u8, contents: []const u8) !void {
    std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = contents,
        .flags = .{ .exclusive = true },
    }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
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

fn moduleManifestTemplate(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\name = "{s}"
        \\version = "0.0.0"
        \\minimum_argi_version = "{s}"
        \\
    ,
        .{ package_name, argi_version.current },
    );
}

fn projectManifestTemplate(allocator: std.mem.Allocator, package_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        \\name = "{s}"
        \\version = "0.0.0"
        \\minimum_argi_version = "{s}"
        \\
        \\[build]
        \\default_entrypoint = "main"
        \\
        \\[entrypoints.main]
        \\path = "source/entrypoints/main"
        \\
    ,
        .{ package_name, argi_version.current },
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
        \\Argi module scaffolded as an application.
        \\
        \\Build the default entrypoint with:
        \\
        \\```sh
        \\argi build
        \\```
        \\
        \\Run it with:
        \\
        \\```sh
        \\argi run
        \\```
        \\
    ,
        .{package_name},
    );
}

fn expectFileExists(io: std.Io, path: []const u8) !void {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    file.close(io);
}

fn expectFileMissing(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    return error.UnexpectedFile;
}

fn expectFileContains(io: std.Io, path: []const u8, expected: []const u8) !void {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, expected) != null);
}

fn expectFileOmits(io: std.Io, path: []const u8, forbidden: []const u8) !void {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, forbidden) == null);
}

test "init module scaffolds minimal files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try std.fs.path.resolve(std.testing.allocator, &.{ ".", ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(tmp_root);
    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "sample_module" });
    defer std.testing.allocator.free(module_root);

    try initAtPath(std.testing.allocator, std.testing.io, .module, module_root);

    const readme = try std.fs.path.join(std.testing.allocator, &.{ module_root, "README.md" });
    defer std.testing.allocator.free(readme);
    const manifest = try std.fs.path.join(std.testing.allocator, &.{ module_root, "argi.toml" });
    defer std.testing.allocator.free(manifest);
    const gitignore = try std.fs.path.join(std.testing.allocator, &.{ module_root, ".gitignore" });
    defer std.testing.allocator.free(gitignore);
    const main_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "main.rg" });
    defer std.testing.allocator.free(main_path);

    try expectFileExists(std.testing.io, readme);
    try expectFileExists(std.testing.io, manifest);
    try expectFileExists(std.testing.io, gitignore);
    try expectFileMissing(std.testing.io, main_path);
    try expectFileContains(std.testing.io, manifest, "version = \"0.0.0\"\n");
    try expectFileContains(std.testing.io, manifest, "minimum_argi_version = \"0.1.0\"\n");
    try expectFileOmits(std.testing.io, manifest, "kind = ");
    try expectFileOmits(std.testing.io, manifest, "[entrypoints.");
}

test "init project scaffolds basic layout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try std.fs.path.resolve(std.testing.allocator, &.{ ".", ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(tmp_root);
    const project_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "sample_project" });
    defer std.testing.allocator.free(project_root);

    try initAtPath(std.testing.allocator, std.testing.io, .project, project_root);

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

    try expectFileExists(std.testing.io, entry_main);
    try expectFileExists(std.testing.io, manifest);
    try expectFileExists(std.testing.io, gitignore);
    try expectFileMissing(std.testing.io, public_dir);
    try expectFileMissing(std.testing.io, private_dir);
    try expectFileContains(std.testing.io, manifest, "version = \"0.0.0\"\n");
    try expectFileContains(std.testing.io, manifest, "minimum_argi_version = \"0.1.0\"\n");
    try expectFileContains(std.testing.io, manifest, "[build]\n");
    try expectFileContains(std.testing.io, manifest, "default_entrypoint = \"main\"\n");
    try expectFileContains(std.testing.io, manifest, "[entrypoints.main]\n");
    try expectFileContains(std.testing.io, manifest, "path = \"source/entrypoints/main\"\n");
    try expectFileOmits(std.testing.io, manifest, "kind = ");
}
