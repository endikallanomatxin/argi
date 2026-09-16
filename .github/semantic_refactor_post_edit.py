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

# `type_initializer.type_decl` identifies the source declaration, but it does
# not identify a concrete runtime type for parameterized declarations. The
# GlobalSG node's `ty` is the already-resolved constructor result and is the
# authoritative runtime type for both ordinary and generic construction.
codegen = Path("src/5_codegen/global_codegen.zig")
text = codegen.read_text()
old = '''            .type_initializer => |initializer| try self.typeInitializer(initializer),
'''
new = '''            .type_initializer => |initializer| try self.typeInitializer(initializer, node.ty),
'''
if text.count(old) != 1:
    raise RuntimeError(f"type initializer dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    fn typeInitializer(self: *CodeGenerator, initializer: anytype) !TypedValue {
        const declaration = self.graph.declarations.items[@intFromEnum(initializer.type_decl)];
        const ty = declaration.type_id orelse return CodegenError.InvalidType;
        const type_ref = try self.toLLVMType(ty);
        const storage = c.LLVMBuildAlloca(self.builder, type_ref, "type.init.tmp");
        try self.typeInitializerInto(initializer, storage);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, storage, "type.init"), .type_ref = type_ref, .ty = ty };
    }
'''
new = '''    fn typeInitializer(self: *CodeGenerator, initializer: anytype, maybe_ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const ty = maybe_ty orelse return CodegenError.InvalidType;
        const type_ref = try self.toLLVMType(ty);
        const storage = c.LLVMBuildAlloca(self.builder, type_ref, "type.init.tmp");
        try self.typeInitializerInto(initializer, storage);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, storage, "type.init"), .type_ref = type_ref, .ty = ty };
    }
'''
if text.count(old) != 1:
    raise RuntimeError(f"type initializer implementation anchor changed: {text.count(old)}")
codegen.write_text(text.replace(old, new, 1))

subprocess.run([
    "zig", "fmt",
    "src/3_syntax/syntaxer.zig",
    "src/0_commands/frontend_pipeline.zig",
    "src/4_semantics/global/constructors.zig",
    "src/4_semantics/global/generics.zig",
    "src/4_semantics/global/generic_functions.zig",
    "src/5_codegen/global_codegen.zig",
], check=True)

# Validate inference with the existing runtime test, then independently cover
# the contextual path where the generic argument can come entirely from the
# expected destination type.
Path(".github/semantic_refactor_test_command").write_text(r'''zig build test-programs -Dtest-filter=feature_tests/types/17_generic_type_initializer_from_init

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cat > "$tmp_dir/main.rg" <<'EOF'
main () -> (.status_code: Int32) := {
    contextual : Range#(.t: Int32) = Range(.end = 4)
    status_code = 0
}
EOF
./zig-out/bin/argi build "$tmp_dir"
''')
