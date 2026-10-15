const std = @import("std");
const module_sg = @import("../4_semantics/module/graph.zig");
const codec = @import("module_cache_codec.zig");
const builtin = @import("builtin");
const build_options = @import("frontend_build_options");

pub const Fingerprint = [32]u8;
pub const ContentHash = std.crypto.hash.Blake3;

pub fn finishHash(hash: *const ContentHash) Fingerprint {
    var fingerprint: Fingerprint = undefined;
    hash.final(&fingerprint);
    return fingerprint;
}

/// Session-owned canonical modules, independent of an editor or executor.
/// Global linking and safety consume immutable snapshots and are never cached
/// here. Entry leases keep a snapshot alive if another compilation replaces it.
/// Access is serialized by the owning session; leases do not provide locking.
pub const ModuleCache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(*Entry) = .empty,
    retained_bytes: usize = 0,
    limits: Limits,
    hits: usize = 0,
    misses: usize = 0,
    disk_hits: usize = 0,
    disk_rejections: usize = 0,
    disk_write_failures: usize = 0,
    disk: ?Disk = null,

    const Disk = struct {
        io: std.Io,
        root: []u8,
    };

    pub const Limits = struct {
        bytes: usize = 64 * 1024 * 1024,
        modules: usize = 256,
    };

    pub const Entry = struct {
        backing_allocator: std.mem.Allocator,
        arena: std.heap.ArenaAllocator,
        graph: module_sg.ModuleSemanticGraph = .{},
        fingerprint: Fingerprint,
        references: usize = 1,
        persisted: bool = false,

        pub fn allocator(self: *Entry) std.mem.Allocator {
            return self.arena.allocator();
        }

        pub fn retain(self: *Entry) void {
            self.references += 1;
        }

        pub fn release(self: *Entry) void {
            self.references -= 1;
            if (self.references != 0) return;
            const backing = self.backing_allocator;
            self.arena.deinit();
            backing.destroy(self);
        }

        pub fn storageBytes(self: *const Entry) usize {
            return @sizeOf(Entry) + self.arena.queryCapacity();
        }
    };

    pub fn init(allocator: std.mem.Allocator, limits: Limits) ModuleCache {
        return .{ .allocator = allocator, .limits = limits };
    }

    pub fn deinit(self: *ModuleCache) void {
        for (self.entries.items) |entry| entry.release();
        if (self.disk) |disk| self.allocator.free(disk.root);
        self.entries.deinit(self.allocator);
        self.entries = .empty;
        self.retained_bytes = 0;
    }

    pub fn enablePersistence(self: *ModuleCache, io: std.Io, cache_root: []const u8) !void {
        const root = try std.fs.path.join(self.allocator, &.{ cache_root, "frontend", "v1" });
        if (self.disk) |previous| self.allocator.free(previous.root);
        self.disk = .{ .io = io, .root = root };
    }

    pub fn create(self: *ModuleCache, fingerprint: Fingerprint) !*Entry {
        const entry = try self.allocator.create(Entry);
        entry.* = .{
            .backing_allocator = self.allocator,
            .arena = std.heap.ArenaAllocator.init(self.allocator),
            .fingerprint = fingerprint,
        };
        return entry;
    }

    pub fn acquire(self: *ModuleCache, dir: []const u8, fingerprint: Fingerprint) ?*Entry {
        for (self.entries.items, 0..) |entry, index| {
            if (!std.mem.eql(u8, entry.graph.module_dir, dir)) continue;
            if (!std.mem.eql(u8, &entry.fingerprint, &fingerprint)) break;
            _ = self.entries.orderedRemove(index);
            self.entries.appendAssumeCapacity(entry);
            entry.retain();
            self.hits += 1;
            return entry;
        }
        if (self.disk != null) {
            if (self.load(dir, fingerprint) catch |err| blk: {
                if (err != error.FileNotFound) self.disk_rejections += 1;
                break :blk null;
            }) |entry| {
                self.hits += 1;
                self.disk_hits += 1;
                return entry;
            }
        }
        self.misses += 1;
        return null;
    }

    /// Only successfully finished modules may enter the cache. Global failures
    /// do not invalidate module-local work; failed local lowering is never stored.
    pub fn publish(self: *ModuleCache, entry: *Entry) !void {
        std.debug.assert(entry.graph.semantic.local_semantics_complete);
        for (self.entries.items, 0..) |previous, index| {
            if (previous == entry) {
                self.persist(entry);
                return;
            }
            if (std.mem.eql(u8, previous.graph.module_dir, entry.graph.module_dir)) {
                self.remove(index);
                break;
            }
        }
        self.persist(entry);
        const bytes = entry.storageBytes();
        if (bytes > self.limits.bytes or self.limits.modules == 0) return;
        while (self.entries.items.len != 0 and
            (self.entries.items.len >= self.limits.modules or self.retained_bytes > self.limits.bytes - bytes))
        {
            self.remove(0);
        }
        try self.entries.append(self.allocator, entry);
        entry.retain();
        self.retained_bytes += bytes;
    }

    fn filePath(self: *ModuleCache, dir: []const u8) ![]u8 {
        var fingerprint: Fingerprint = undefined;
        ContentHash.hash(dir, &fingerprint, .{});
        const name = std.fmt.bytesToHex(fingerprint, .lower);
        return std.fmt.allocPrint(self.allocator, "{s}/{s}.module", .{ self.disk.?.root, name });
    }

    fn load(self: *ModuleCache, dir: []const u8, fingerprint: Fingerprint) !?*Entry {
        const disk = self.disk.?;
        const path = try self.filePath(dir);
        defer self.allocator.free(path);
        const data = try std.Io.Dir.cwd().readFileAlloc(disk.io, path, self.allocator, .limited(codec.max_file_bytes));
        defer self.allocator.free(data);
        const entry = try self.create(fingerprint);
        errdefer entry.release();
        entry.graph = try codec.decode(entry.allocator(), data, fingerprint);
        if (!std.mem.eql(u8, entry.graph.module_dir, dir)) return error.InvalidCache;
        entry.persisted = true;
        return entry;
    }

    fn persist(self: *ModuleCache, entry: *Entry) void {
        if (self.disk == null or entry.persisted) return;
        self.write(entry) catch {
            self.disk_write_failures += 1;
            return;
        };
        entry.persisted = true;
    }

    fn write(self: *ModuleCache, entry: *Entry) !void {
        const disk = self.disk.?;
        const path = try self.filePath(entry.graph.module_dir);
        defer self.allocator.free(path);
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        const data = try codec.encode(temporary.allocator(), &entry.graph, entry.fingerprint);
        var atomic = try std.Io.Dir.cwd().createFileAtomic(disk.io, path, .{ .make_path = true, .replace = true });
        defer atomic.deinit(disk.io);
        var buffer: [8192]u8 = undefined;
        var writer = atomic.file.writer(disk.io, &buffer);
        try writer.interface.writeAll(data);
        try writer.interface.flush();
        try atomic.replace(disk.io);
    }

    fn remove(self: *ModuleCache, index: usize) void {
        const entry = self.entries.orderedRemove(index);
        self.retained_bytes -= entry.storageBytes();
        entry.release();
    }
};

/// Length framing distinguishes source boundaries and optional configuration.
/// FileId is intentionally absent: durable provenance is module-local, while
/// paths and source ordering are part of the content identity.
pub fn hashBytes(hash: *ContentHash, bytes: []const u8) void {
    const length: u64 = @intCast(bytes.len);
    hash.update(std.mem.asBytes(&length));
    hash.update(bytes);
}

/// Source and target configuration are explicit inputs to persistent snapshots.
/// The process-local cache uses the same key so adding persistence cannot alter
/// which semantic decisions are eligible for reuse.
pub fn hashConfiguration(hash: *ContentHash) void {
    hash.update(&build_options.cache_build_id);
    hashBytes(hash, builtin.zig_version_string);
    hashBytes(hash, @tagName(builtin.target.cpu.arch));
    hashBytes(hash, @tagName(builtin.target.os.tag));
    hashBytes(hash, @tagName(builtin.target.abi));
    hashBytes(hash, @tagName(builtin.mode));
    const version = codec.format_version;
    hash.update(std.mem.asBytes(&version));
}
