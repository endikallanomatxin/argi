Counter : Abstract = (bump(.self: $&Self) -> ())
Box : Type = (.value: Int32)
Box implements Counter
bump(.self: $&Box) -> () := { self&.value = self&.value + 1 }
wrap#(.t: Type: Counter)(.value: &t) -> (.result: Virtual#(.abstract: Counter)) := {
    result = to_virtual#(.abstract: Counter)(.value = value)
}
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= wrap#(.t: Box)(.value = &box).result
    bump(.self = $&handle)
}
