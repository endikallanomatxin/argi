//! Explicit fixture expectations and isolation. Discovery never infers test
//! behavior from directory names, source text, or numeric prefixes.
const std = @import("std");

pub const Isolation = enum { fixture, exclusive };
pub const Kind = enum { build, reject, run, run_failure, vm };
pub const Step = struct {
    kind: Kind,
    status: ?u8 = null,
    args: []const []const u8 = &.{},
    stdin: ?[]const u8 = null,
    stdout: ?[]const u8 = null,
    stderr: ?[]const u8 = null,
    diagnostic: ?[]const u8 = null,
    forbidden_stdout: []const []const u8 = &.{},
    forbidden_stderr: []const []const u8 = &.{},
};
pub const Case = struct { name: ?[]const u8 = null, steps: []const Step };
pub const Descriptor = struct { version: u32, isolation: Isolation, cases: []const Case };
pub const Custom = struct { name: []const u8, isolation: Isolation, fixture: ?[]const u8 = null, covers: []const []const u8 };
const Registry = struct { version: u32, tests: []const Custom };
pub const Entry = struct {
    name: []const u8,
    fixture: ?[]const u8,
    isolation: Isolation,
    custom: bool,
    steps: []const Step = &.{},
};

pub fn validateSteps(steps: []const Step) !void {
    if (steps.len == 0) return error.EmptyFixtureCase;
    var built = false;
    for (steps) |step| {
        switch (step.kind) {
            .build => {
                if (step.status != null or step.stdout != null or step.stderr != null or step.diagnostic != null) return error.InvalidBuildExpectation;
                built = true;
            },
            .reject => {
                if (step.diagnostic == null and step.stderr == null) return error.MissingRejectionDiagnostic;
                if (step.status != null or step.stdout != null) return error.InvalidRejectionExpectation;
                built = false;
            },
            .run => {
                if (!built) return error.RunWithoutBuild;
                if (step.status == null) return error.MissingExitStatus;
                if (step.stdout != null and step.stderr != null) return error.CombinedStreamExpectationUnsupported;
                if ((step.args.len != 0 or step.stdin != null) and step.stdout == null) return error.MissingStdoutExpectation;
                if (step.diagnostic != null) return error.InvalidRunExpectation;
            },
            .run_failure => {
                if (!built) return error.RunWithoutBuild;
                if (step.status != null or step.stdout != null or step.stderr != null or step.diagnostic != null) return error.InvalidRunFailureExpectation;
            },
            .vm => {
                if (step.status == null) return error.MissingExitStatus;
                if (step.stdout != null or step.stderr != null) return error.InvalidVmExpectation;
            },
        }
        if (step.kind != .run and (step.args.len != 0 or step.stdin != null)) return error.UnusedProcessArguments;
        if (step.kind != .reject and (step.forbidden_stdout.len != 0 or step.forbidden_stderr.len != 0)) return error.UnusedDiagnosticExclusions;
    }
}

pub fn matchesFilters(name: []const u8, filters: []const []const u8) bool {
    if (filters.len == 0) return true;
    for (filters) |filter| if (std.mem.indexOf(u8, name, filter) != null) return true;
    return false;
}

pub fn validateFixturePath(path: []const u8) !void {
    var parts = std.mem.splitScalar(u8, path, '/');
    if (!std.mem.eql(u8, parts.next() orelse "", "tests") or !std.mem.eql(u8, parts.next() orelse "", "feature_tests")) return error.InvalidFixturePath;
    for (0..2) |_| {
        const part = parts.next() orelse return error.InvalidFixturePath;
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..") or std.mem.indexOfScalar(u8, part, '\\') != null) return error.InvalidFixturePath;
    }
    if (parts.next() != null) return error.InvalidFixturePath;
}

pub const Catalog = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,

    pub fn init(self: *Catalog, allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !void {
        self.* = .{ .arena = .init(allocator) };
        errdefer self.deinit();
        const a = self.arena.allocator();
        var root = try std.Io.Dir.cwd().openDir(io, root_path, .{});
        defer root.close(io);
        const registry = try readJson(Registry, root, io, a, "tests/custom_tests.json");
        if (registry.version != 1) return error.UnsupportedTestDescriptorVersion;
        var covered: std.StringHashMapUnmanaged(void) = .empty;
        for (registry.tests) |custom| {
            if (custom.isolation == .fixture) {
                const fixture = custom.fixture orelse return error.MissingFixtureIsolationGroup;
                try validateFixturePath(fixture);
            } else if (custom.fixture != null) return error.UnusedFixtureIsolationGroup;
            for (custom.covers) |path| {
                try validateFixturePath(path);
                const main_path = try std.fmt.allocPrint(a, "{s}/main.rg", .{path});
                try root.access(io, main_path, .{});
                try covered.put(a, path, {});
            }
            try self.add(.{ .name = custom.name, .fixture = custom.fixture, .isolation = custom.isolation, .custom = true });
        }
        const custom_count = self.entries.items.len;
        var features = try root.openDir(io, "tests/feature_tests", .{ .iterate = true });
        defer features.close(io);
        var categories = features.iterate();
        while (try categories.next(io)) |category| {
            if (category.kind != .directory) continue;
            var directory = try features.openDir(io, category.name, .{ .iterate = true });
            defer directory.close(io);
            var cases = directory.iterate();
            while (try cases.next(io)) |case| {
                if (case.kind != .directory) continue;
                const path = try std.fmt.allocPrint(a, "tests/feature_tests/{s}/{s}", .{ category.name, case.name });
                const main_path = try std.fmt.allocPrint(a, "{s}/main.rg", .{path});
                root.access(io, main_path, .{}) catch |err| switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                };
                const descriptor_path = try std.fmt.allocPrint(a, "{s}/test.json", .{path});
                root.access(io, descriptor_path, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        if (!covered.contains(path) and try substantive(root, io, a, main_path)) {
                            std.debug.print("fixture has neither test.json nor custom coverage: {s}\n", .{path});
                            return error.MissingFeatureTestCoverage;
                        }
                        continue;
                    },
                    else => return err,
                };
                const descriptor = try readJson(Descriptor, root, io, a, descriptor_path);
                if (descriptor.version != 1) return error.UnsupportedTestDescriptorVersion;
                if (descriptor.cases.len == 0) return error.EmptyFixtureDescriptor;
                for (descriptor.cases) |fixture_case| {
                    validateSteps(fixture_case.steps) catch |err| {
                        std.debug.print("invalid fixture expectations in {s}: {s}\n", .{ descriptor_path, @errorName(err) });
                        return err;
                    };
                    try self.add(.{ .name = fixture_case.name orelse path["tests/".len..], .fixture = path, .isolation = descriptor.isolation, .custom = false, .steps = fixture_case.steps });
                }
            }
        }
        // Filesystem enumeration order must not affect execution or reports.
        std.mem.sort(Entry, self.entries.items[custom_count..], {}, struct {
            fn less(_: void, left: Entry, right: Entry) bool {
                return std.mem.lessThan(u8, left.name, right.name);
            }
        }.less);
        self.names.clearRetainingCapacity();
        for (self.entries.items, 0..) |entry, index| try self.names.put(a, entry.name, index);
    }

    pub fn deinit(self: *Catalog) void {
        self.arena.deinit();
        self.* = undefined;
    }

    fn add(self: *Catalog, entry: Entry) !void {
        if (entry.name.len == 0) return error.EmptyTestName;
        const a = self.arena.allocator();
        const indexed = try self.names.getOrPut(a, entry.name);
        if (indexed.found_existing) return error.DuplicateTestName;
        indexed.value_ptr.* = self.entries.items.len;
        try self.entries.append(a, entry);
    }

    pub fn customName(self: *const Catalog, compiled_name: []const u8) ?[]const u8 {
        var name = compiled_name;
        while (true) {
            if (self.names.get(name)) |index| return if (self.entries.items[index].custom) name else null;
            const dot = std.mem.indexOfScalar(u8, name, '.') orelse return null;
            name = name[dot + 1 ..];
        }
    }
};

fn readJson(comptime T: type, root: std.Io.Dir, io: std.Io, allocator: std.mem.Allocator, path: []const u8) !T {
    const bytes = try root.readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
    return std.json.parseFromSliceLeaky(T, allocator, bytes, .{ .allocate = .alloc_always }) catch |err| {
        std.debug.print("invalid test descriptor {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
}

fn substantive(root: std.Io.Dir, io: std.Io, allocator: std.mem.Allocator, path: []const u8) !bool {
    const bytes = try root.readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const text = std.mem.trim(u8, line, " \t\r");
        if (text.len != 0 and !std.mem.startsWith(u8, text, "--")) return true;
    }
    return false;
}
