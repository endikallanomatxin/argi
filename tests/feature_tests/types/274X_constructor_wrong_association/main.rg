First := (.value: Int32)

Second := (.value: Int32)

FirstInitArgs: Type = ()

implement Init#(First, FirstInitArgs) (
    .Result : Type = Second

    .init = FirstInitArgs -> (.result: Result) {
        result = (.value = 1)
    }
)

main := () -> (.status_code: Int32 = 0) {
    value ::= First()
    status_code = value.value
}
