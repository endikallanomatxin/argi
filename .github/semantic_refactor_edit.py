from pathlib import Path

core = Path("src/4_semantics/global/core.zig")
text = core.read_text()
old = '''        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        if (types.equal(self.graph, actual_pointer.child, expected_pointer.child)) return true;
        return switch (self.graph.types.items[@intFromEnum(actual_pointer.child)]) {
            .virtual => |abstract_type| types.equal(self.graph, abstract_type, expected_pointer.child),
            else => false,
        };
'''
new = '''        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        if (types.equal(self.graph, actual_pointer.child, expected_pointer.child)) return true;
        // `Any` is the wildcard value type. A reference to a concrete value is
        // therefore compatible with `&Any`/`$&Any`, subject to the same
        // mutability rule above. Keep this at the pointee boundary rather than
        // recursively making pointer constructors covariant: e.g. `&&Int32`
        // must not silently become `&&Any` when the outer reference can expose
        // a differently typed pointer slot.
        if (types.isBuiltin(self.graph, expected_pointer.child, .Any)) return true;
        return switch (self.graph.types.items[@intFromEnum(actual_pointer.child)]) {
            .virtual => |abstract_type| types.equal(self.graph, abstract_type, expected_pointer.child),
            else => false,
        };
'''
if text.count(old) != 1:
    raise RuntimeError(f"reference compatibility anchor changed: {text.count(old)}")
core.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/polymorphism/01_multiple_dispatch "
    "-Dtest-filter=feature_tests/polymorphism/02X_multiple_dispatch_ambiguous\n"
)
Path(".git/semantic-refactor-message").write_text("Allow concrete references to match Any references\n")
