from pathlib import Path
import subprocess

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()
old = '''        const iterable_contract_name, const conversion_name, const iterable_mutable = switch (value.mode) {
            .value => .{ "Iterable", "to_iterator", false },
            .borrow => .{ "ROPointerIterable", "to_ro_pointer_iterator", false },
            .mut_borrow => .{ "RWPointerIterable", "to_rw_pointer_iterator", true },
        };
'''
new = '''        const ForProtocol = struct {
            iterable_contract: []const u8,
            conversion: []const u8,
            mutable: bool,
        };
        const protocol: ForProtocol = switch (value.mode) {
            .value => .{ .iterable_contract = "Iterable", .conversion = "to_iterator", .mutable = false },
            .borrow => .{ .iterable_contract = "ROPointerIterable", .conversion = "to_ro_pointer_iterator", .mutable = false },
            .mut_borrow => .{ .iterable_contract = "RWPointerIterable", .conversion = "to_rw_pointer_iterator", .mutable = true },
        };
        const iterable_contract_name = protocol.iterable_contract;
        const conversion_name = protocol.conversion;
        const iterable_mutable = protocol.mutable;
'''
if text.count(old) != 1:
    raise RuntimeError(f"for protocol syntax anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    fn resolveForEach(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const core = self.core orelse return .deferred;
'''
new = '''    fn resolveForEach(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !resolution.Result {
        @setEvalBranchQuota(5000);
        const core = self.core orelse return .deferred;
'''
if text.count(old) != 1:
    raise RuntimeError(f"for-each quota anchor changed: {text.count(old)}")
control.write_text(text.replace(old, new, 1))

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/core.zig",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/global/control.zig",
    "src/4_semantics/global/semantizer.zig",
], check=True)
