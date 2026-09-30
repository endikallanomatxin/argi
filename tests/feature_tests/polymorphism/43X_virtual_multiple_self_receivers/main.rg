A : Abstract = (compare(.self: &Self, .other: &Self) -> (.value: Int32))
Box : Type = (.value: Int32)
Box implements A
compare(.self: &Box, .other: &Box) -> (.value: Int32) := { value = self&.value }
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
