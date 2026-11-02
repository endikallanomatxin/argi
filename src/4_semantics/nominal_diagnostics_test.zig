const checkSource = @import("source_test_support.zig").checkSource;

test "source nominal diagnostics 291X_nominal_record_base_mismatch" {
    const source =
        \\VertexId := (.value: UIntNative)
        \\
        \\accept := (.value: VertexId) -> () {}
        \\
        \\main := () -> () {
        \\    raw: UIntNative = 1
        \\    accept(.value = raw)
        \\}
    ;
    try checkSource("291X_nominal_record_base_mismatch", source, null, "no function named 'accept' accepts arguments (.value: UIntNative)", false);
}

test "source nominal diagnostics 296X_nominal_record_assignment" {
    const source =
        \\VertexId := (.value: UIntNative)
        \\
        \\EdgeId := (.value: UIntNative)
        \\
        \\main := () -> () {
        \\    edge: EdgeId = (.value = 7)
        \\    vertex: VertexId = edge
        \\}
    ;
    try checkSource("296X_nominal_record_assignment", source, null, "distinct nominal types require explicit conversion", false);
}

test "source nominal diagnostics 309X_nested_nominal_record_assignment" {
    const source =
        \\First := (.value: Bool)
        \\Second := (.value: Bool)
        \\Container := (.item: First)
        \\
        \\main := () -> () {
        \\    other: Second = (.value = true)
        \\    container: Container = (.item = other)
        \\}
    ;
    try checkSource("309X_nested_nominal_record_assignment", source, null, "distinct nominal types require explicit conversion", false);
}

test "source nominal diagnostics 311X_nominal_construction_recontextualization" {
    const source =
        \\First := (.value: Bool)
        \\Second := (.value: Bool)
        \\
        \\main := () -> () {
        \\    first: First = Second(.value = true)
        \\}
    ;
    try checkSource("311X_nominal_construction_recontextualization", source, null, "distinct nominal types require explicit conversion", false);
}

test "source nominal diagnostics 325X_type_family_signature_mismatch" {
    const source =
        \\Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)
        \\
        \\accept := #(.Family: #(.Item: Type) Type) () -> () {}
        \\
        \\main := () -> () {
        \\    accept#(.Family = Pair)()
        \\}
    ;
    try checkSource("325X_type_family_signature_mismatch", source, null, "type-family argument does not match its parameter signature", false);
}
test "source nominal diagnostics accept matching type families" {
    const source =
        \\Box := #(.Item: Type) (.value: Item)
        \\accept := #(.Family: #(.Item: Type) Type) () -> () {}
        \\main := () -> () { accept#(.Family = Box)() }
    ;
    try checkSource("family_control", source, null, null, true);
}
