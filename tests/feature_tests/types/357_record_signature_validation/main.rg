Inputs := (.left: Int32, .right: Int32 = 2)

Outputs := (.total: Int32, .extra: Int32 = 0)

sum := Inputs -> Outputs { total = left + right }

verify := () -> () {
    input: Inputs = (.left = 40)
    expected: Outputs = (.total = 42)
    actual: Outputs = sum(.left = 40)
    reordered: Outputs = sum(.right = input.right, .left = input.left)
    if actual.total != expected.total or actual.extra != expected.extra { abort }
    if reordered.total != expected.total or reordered.extra != expected.extra { abort }
    nested: (.value: Outputs) = (.value = (.total = 42))
    if nested.value.total != actual.total or nested.value.extra != actual.extra { abort }
}

known ::= #run () -> (.result: Bool) {
    verify()
    result = true
}

main := () -> () {
    verify()
    if known {} else { abort }
}
