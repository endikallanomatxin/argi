Box: Type = (.value: Int32)

escape#(.t: Type)(.value: t) -> (.result: $&Box) := {
    result = Box(.value = value) | $&_
}

main() -> (.status_code: Int32 = 0) := {
    borrowed ::= escape(.value = 7).result
    if borrowed&.value != 7 { status_code = 1 }
}
