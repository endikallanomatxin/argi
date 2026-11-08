main := (.system: System) -> (.status_code: Int32 = 7) {
    assume writer ::= $&system.terminal&.stderr
    if system.args&.count == 1 { return }
    expected: [9]StringView = (
        "--output", "--emit-llvm", "--vm", "--help", "-v", "", "a b", "--", "á;$(no)"
    )
    if system.args&.count != 10 { abort }
    index :: UIntNative = 0
    while index < 9 {
        value ::= argument_view_at(system.args, .index = index + 1)!!!
        if value != expected[index] { abort }
        index = index + 1
    }
}
