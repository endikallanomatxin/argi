First := (.value: Int32)

Second := (.value: Int32)

implement Init#(First, ()) (
    .Result : Type = Second
    .init   = (.args: ()) -> (.result: Result) {
        result = (.value = 1)
    }
)

main := () -> (.status_code: Int32 = 0) {
    value ::= First()
    status_code = value.value
}
