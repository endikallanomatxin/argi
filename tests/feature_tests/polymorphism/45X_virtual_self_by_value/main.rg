A : Abstract = (consume(.self: Self) -> ())
Box : Type = (.value: Int32)
Box implements A
consume(.self: Box) -> () := {}
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
