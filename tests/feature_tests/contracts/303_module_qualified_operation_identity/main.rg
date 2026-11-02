first := import ("./first")
second := import ("./second")

through_generic := #(.T: Type) (.value: T) -> (.result: Int32) {
    result = first.query(.value = value) + second.query(.value = value)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    if first.query(.value = 10) != 11 { status_code = 1 }
    if second.query(.value = 10) != 12 { status_code = 2 }
    if through_generic(.value = 10) != 23 { status_code = 3 }
    if first.Query#(Int32).query(.value = 10) != 11 { status_code = 4 }
}
