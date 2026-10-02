A : Abstract = (borrow(.self: &Self) -> (.value: &Self))
Box : Type = (.value: Int32)
Box implements A
borrow(.self: &Box) -> (.value: &Box) := { value = self }
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
