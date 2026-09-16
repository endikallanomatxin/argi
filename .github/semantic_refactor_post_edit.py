from pathlib import Path
import subprocess

constructors = Path("src/4_semantics/global/constructors.zig")
text = constructors.read_text()
old = '''        var generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        if (generics.isParameterizedTypeDeclaration(declaration_id))
            return self.resolveImplicitGenericCall(module_index, o, value, reference, declaration_id, input);
'''
new = '''        var type_generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        if (type_generics.isParameterizedTypeDeclaration(declaration_id))
            return self.resolveImplicitGenericCall(module_index, o, value, reference, declaration_id, input);
'''
if text.count(old) != 1:
    raise RuntimeError(f"constructor generic query anchor changed: {text.count(old)}")
constructors.write_text(text.replace(old, new, 1))

subprocess.run([
    "zig", "fmt",
    "src/3_syntax/syntaxer.zig",
    "src/0_commands/frontend_pipeline.zig",
    "src/4_semantics/global/constructors.zig",
    "src/4_semantics/global/generics.zig",
    "src/4_semantics/global/generic_functions.zig",
], check=True)

# The Range feature tests continue into for-each lowering, which is a separate
# unresolved cluster. Validate this edit at its actual boundary: implicit
# generic construction must compile both with argument inference and with a
# contextual expected generic type.
Path(".github/semantic_refactor_test_command").write_text(r'''tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cat > "$tmp_dir/main.rg" <<'EOF'
main () -> (.status_code: Int32) := {
    inferred ::= Range(.start = 1, .end = 5)
    contextual : Range#(.t: Int32) = Range(.end = 4)
    status_code = 0
}
EOF
./zig-out/bin/argi build "$tmp_dir"
''')
