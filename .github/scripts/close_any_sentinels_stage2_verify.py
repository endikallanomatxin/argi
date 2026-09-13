from pathlib import Path

p = Path("src/4_semantics/module/parameterized/ir_verify.zig")
text = p.read_text()
old = """    for (storage.bindings.items) |value| try payload.binding(ir.Ids, value, bounds);\n"""
new = """    for (storage.unresolved_binding_types.items, 0..) |binding, marker_index| {
        try require(verify.idFits(binding, storage.bindings.items.len));
        for (storage.unresolved_binding_types.items[0..marker_index]) |previous|
            try require(previous != binding);
        try require(storage.bindings.items[@intFromEnum(binding)].ty == ir.unresolved_binding_type_poison);
    }
    for (storage.bindings.items, 0..) |value, raw| {
        const id: ir.ParameterizedBindingId = @enumFromInt(@as(u32, @intCast(raw)));
        if (storage.bindingType(id) != null) {
            try payload.binding(ir.Ids, value, bounds);
        } else {
            // Incomplete type is represented only by sparse construction metadata.
            // Every other binding reference remains fully verified.
            try require(verify.stringFits(value.name, graph.strings.items));
            try require(verify.sourceFits(value.source, graph.file_offsets.items.len));
            try require(verify.optionalIdFits(value.initialization, storage.nodes.items.len));
        }
    }
"""
if old not in text:
    raise SystemExit("parameterized binding verifier anchor not found")
p.write_text(text.replace(old, new, 1))
