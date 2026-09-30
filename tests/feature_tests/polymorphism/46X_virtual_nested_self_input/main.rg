A : Abstract = (inspect(.self: &Self, .nested: (.value: &Self)) -> ())
Box : Type = (.value: Int32)
Box implements A
inspect(.self: &Box, .nested: (.value: &Box)) -> () := {}
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
