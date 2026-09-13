from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old in text:
        p.write_text(text.replace(old, new, 1))
        return
    if new in text:
        return
    raise SystemExit(f"expected anchor not found in {path}: {old[:160]!r}")


# A payloadless error variant has no value. `Void` is the semantic type of that
# absence; `Any` would incorrectly turn a representation fallback into a
# wildcard type.
replace_once(
    "src/4_semantics/global/errors.zig",
    "        const error_payload = err.variant.payload_type orelse try self.builtin(.Any);\n",
    "        const error_payload = err.variant.payload_type orelse try self.builtin(.Void);\n",
)

# The remaining Any in inferred `!T` is deliberate language semantics: while
# the inferred error family is open, its `error` payload accepts any error
# reason payload. It is not unresolved construction state.
replace_once(
    "src/4_semantics/global/control.zig",
    """        const any = try self.builtin(.Any);
        const source = self.syntheticSource();
""",
    """        // `Any` here is the language wildcard for the still-open error
        // family of `!T`; it is not a missing-type sentinel. Construction holes
        // are represented by explicit resolution metadata elsewhere.
        const open_error_payload = try self.builtin(.Any);
        const source = self.syntheticSource();
""",
)
replace_once(
    "src/4_semantics/global/control.zig",
    """            .name = error_name,
            .payload_type = any,
""",
    """            .name = error_name,
            .payload_type = open_error_payload,
""",
)
