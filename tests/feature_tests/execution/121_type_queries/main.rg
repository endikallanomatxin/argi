observe := (.count: $&Int32) -> (.value: Int32) {
    count&= count&+ 1
    value = 42
}

main := () -> (.status_code: Int32) {
    count :: Int32 = 0
    value :: Int32 = 7
    value_type := type_of(value)
    queried ::= size_of(observe(.count = $&count))
    if count != 0 { abort }
    if queried != 4 { abort }
    if alignment_of(value_type) != 4 { abort }
    if size_of(.type = value_type) != 4 { abort }
    status_code = 42
}
