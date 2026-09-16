from pathlib import Path
import subprocess


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


# A qualified value diagnostic belongs to the qualifier expression (`dep`),
# not the member token. Keep that exact source site while preserving the same
# semantic module path used for lookup.
replace_once(
    "src/4_semantics/module/body_lowerer.zig",
    "                        .module_path = module_path,\n"
    "                        .source = self.sourceRef(node),\n"
    "                    } }, expected);\n",
    "                        .module_path = module_path,\n"
    "                        .source = self.sourceRef(access.value),\n"
    "                    } }, expected);\n",
)

# Type ExternalRef.source is also diagnostic provenance. For `dep.Type`, anchor
# it at the qualifier token; unqualified types retain the type-node location.
replace_once(
    "src/4_semantics/module/type_lowerer.zig",
    "        const external = try self.writer.addExternalRef(.{\n"
    "            .kind = .type,\n"
    "            .module_path = module_path,\n"
    "            .name = name,\n"
    "            .generic_arguments = generic_arguments,\n"
    "            .source = self.sourceRef(node),\n"
    "        });\n",
    "        const external = try self.writer.addExternalRef(.{\n"
    "            .kind = .type,\n"
    "            .module_path = module_path,\n"
    "            .name = name,\n"
    "            .generic_arguments = generic_arguments,\n"
    "            .source = if (qualifier_token) |token_index| .{\n"
    "                .file_index = self.file_index,\n"
    "                .offset = self.tree.tokenLocation(token_index).offset,\n"
    "            } else self.sourceRef(node),\n"
    "        });\n",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/module/entities.zig",
    "src/4_semantics/module/body_lowerer.zig",
    "src/4_semantics/module/type_lowerer.zig",
    "src/4_semantics/global/expressions.zig",
    "src/4_semantics/global/semantizer.zig",
], check=True)
