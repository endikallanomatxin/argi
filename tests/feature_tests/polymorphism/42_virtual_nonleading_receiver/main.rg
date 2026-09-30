A : Abstract = (add(.amount: Int32, .target: $&Self) -> (.value: Int32))
Box : Type = (.value: Int32)
Box implements A
add(.amount: Int32, .target: $&Box) -> (.value: Int32) := {
    target&.value = target&.value + amount
    value = target&.value
}
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
    value ::= add(.amount = 3, .target = $&handle)
    if value != 10 or box.value != 10 { status_code = 1 }
}
