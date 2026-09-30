A : Abstract = (read(.self: &Self, .other: &Virtual#(.abstract: A)) -> (.value: Int32))
Box : Type = (.value: Int32)
Box implements A
read(.self: &Box, .other: &Virtual#(.abstract: A)) -> (.value: Int32) := { value = self&.value }
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = &box)
    value ::= read(.self = &handle, .other = &handle)
    if value != 7 { status_code = 1 }
}
