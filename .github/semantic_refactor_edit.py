from pathlib import Path

resolution = Path("src/4_semantics/global/resolution.zig")
text = resolution.read_text()
old = '''pub const Result = enum(u2) {
    not_applicable,
    deferred,
    resolved,
'''
new = '''pub const Result = enum(u2) {
    not_applicable,
    deferred,
    invalid,
    resolved,
'''
if text.count(old) != 1:
    raise RuntimeError(f"resolution enum anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    pub fn isResolved(self: Result) bool {
        return self == .resolved;
    }

    /// `not_applicable` is an internal strategy result'''
new = '''    pub fn isResolved(self: Result) bool {
        return self == .resolved;
    }

    pub fn isInvalid(self: Result) bool {
        return self == .invalid;
    }

    /// `not_applicable` is an internal strategy result'''
if text.count(old) != 1:
    raise RuntimeError(f"resolution helper anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    try std.testing.expect(!Result.deferred.allowsFallback());
    try std.testing.expect(!Result.resolved.allowsFallback());
    try std.testing.expect(Result.deferred.isDeferred());
}'''
new = '''    try std.testing.expect(!Result.deferred.allowsFallback());
    try std.testing.expect(!Result.invalid.allowsFallback());
    try std.testing.expect(!Result.resolved.allowsFallback());
    try std.testing.expect(Result.deferred.isDeferred());
    try std.testing.expect(Result.invalid.isInvalid());
}'''
if text.count(old) != 1:
    raise RuntimeError(f"resolution test anchor changed: {text.count(old)}")
resolution.write_text(text.replace(old, new, 1))

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()
old = '''    const resolved = try allocator.alloc(bool, total);
    defer allocator.free(resolved);
    @memset(resolved, false);
    var worklists = try PendingWorklists.init(allocator, modules, relocation.offsets.items);
'''
new = '''    const resolved = try allocator.alloc(bool, total);
    defer allocator.free(resolved);
    @memset(resolved, false);
    const invalid = try allocator.alloc(bool, total);
    defer allocator.free(invalid);
    @memset(invalid, false);
    var worklists = try PendingWorklists.init(allocator, modules, relocation.offsets.items);
'''
if text.count(old) != 1:
    raise RuntimeError(f"work-state allocation anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''                    relocation.offsets.items,
                    resolved,
                    worklists.forPhase(phase),
'''
new = '''                    relocation.offsets.items,
                    resolved,
                    invalid,
                    worklists.forPhase(phase),
'''
if text.count(old) != 1:
    raise RuntimeError(f"resolve phase call anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    offsets: []const globalizer.Offsets,
    resolved: []bool,
    work: *std.ArrayList(PendingWorkItem),
'''
new = '''    offsets: []const globalizer.Offsets,
    resolved: []bool,
    invalid: []bool,
    work: *std.ArrayList(PendingWorkItem),
'''
if text.count(old) != 1:
    raise RuntimeError(f"resolve phase signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''        const flat_index: usize = @intCast(item.flat_index);
        const module = &modules[module_index];
        const operation = module.semantic.pending_operations.items[operation_index];
'''
new = '''        const flat_index: usize = @intCast(item.flat_index);
        if (invalid[flat_index]) {
            work.items[write] = item;
            write += 1;
            continue;
        }
        const module = &modules[module_index];
        const operation = module.semantic.pending_operations.items[operation_index];
'''
if text.count(old) != 1:
    raise RuntimeError(f"terminal invalid skip anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''        if (result.isResolved()) {
            resolved[flat_index] = true;
            changed = true;
        } else {
            work.items[write] = item;
            write += 1;
        }
'''
new = '''        if (result.isResolved()) {
            resolved[flat_index] = true;
            changed = true;
        } else {
            if (result.isInvalid()) invalid[flat_index] = true;
            work.items[write] = item;
            write += 1;
        }
'''
if text.count(old) != 1:
    raise RuntimeError(f"terminal invalid result anchor changed: {text.count(old)}")
semantizer.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/types/03_choice_payloads "
    "-Dtest-filter=feature_tests/types/04X_choice_missing_payload "
    "-Dtest-filter=feature_tests/types/10X_choice_unknown_variant "
    "-Dtest-filter=feature_tests/types/11X_choice_payload_access_without_payload\n"
)
Path(".git/semantic-refactor-message").write_text("Track terminal invalid semantic resolutions\n")
