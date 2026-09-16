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
