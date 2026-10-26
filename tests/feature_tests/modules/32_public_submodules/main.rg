ValueAlias: Type = root.branch.leaf.Value

forward := <.T: Type> (.value: T) -> (.result: T) {
    result = root.branch.leaf.identity<.T: T>(value)
}

main := () -> (.status_code: Int32 = 0) {
    value: root.branch.leaf.Value = (.number = 42)
    if value.number != 42 { return 1 }
    if forward<.T: Int32>(13) != 13 { return 8 }
    if root.branch.leaf.identity<.T: Int32>(42) != 42 { return 7 }
    if root.branch.leaf.answer() != 42 { return 2 }
    if root.branch.leaf.answer_value != 42 { return 3 }
    if root.branch.private_answer() != 7 { return 4 }
    local := import ("./tree")
    other: local.branch.leaf.Value = (.number = 12)
    if other.number != 12 { return 5 }
    if root.branch.leaf.record.inner.number != 9 { return 6 }
}
