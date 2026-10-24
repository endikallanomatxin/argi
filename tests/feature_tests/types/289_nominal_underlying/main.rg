VertexId: Type = UIntNative

EdgeId: Type = UIntNative

SmallId: Type = UInt8

NestedId: Type = VertexId

Distance: Type = Float64

Signed: Type = Int64

Enabled: Type = Bool

identity#(.T: Type) := (.value: T) -> (.result: T) {
    result = value
}

accept_id(.value: VertexId) -> (.result: VertexId) := {
    result = value
}

main() -> (.status_code: Int32 = 0) := {
    if accept_id(.value = 3) != 3 { status_code = 10 }
    if identity#(VertexId)(.value = 4) != 4 { status_code = 11 }
    enabled: Enabled = true
    other: Enabled = false
    if enabled == other { status_code = 9 }
    vertex: VertexId = 7
    edge: EdgeId = 9
    next ::= vertex + 1
    if next != 8 or vertex >= next or edge != 9 { status_code = 1 }
    nested: NestedId = 12
    if identity(.value = nested) != 12 { status_code = 2 }
    small: SmallId = 255
    if small / 2 != 127 { status_code = 3 }
    signed: Signed = -8
    if signed / 2 != -4 { status_code = 4 }
    distance: Distance = 1.5
    if distance + 0.5 != 2.0 { status_code = 5 }
    raw ::= unwrap_or_abort(.value = vertex | convert#(.to: UIntNative)(_))
    restored ::= unwrap_or_abort(.value = raw | convert#(.to: VertexId)(_))
    if restored != vertex { status_code = 8 }
    values: [2]VertexId = (3, 4)
    if values[0] != 3 or values[1] != 4 { status_code = 6 }
    if size_of(.type = VertexId) != size_of(.type = UIntNative) { status_code = 7 }
}
