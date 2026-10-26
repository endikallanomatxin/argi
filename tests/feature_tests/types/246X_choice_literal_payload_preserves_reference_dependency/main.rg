Target := (
    .value: UInt8
)

Borrowing := (
    .reference: $&UInt8
)

Result : Type = (
    ..ok Borrowing
    ..error Int32
)

implement InfalliblyCopyable<Borrowing> (
    .copy = (.self: &Borrowing) -> (.value: Borrowing) {
        value = (.reference = self&.reference)
    }
)

implement Deinit<Target> (
    .deinit = (.self: $&Target) -> () {

    }
)

read := (.pointer: $&UInt8) -> (.value: UInt8)  {
    value = pointer&
}

main := () -> (.status_code: Int32 = 0)  {
    target :: Target = (.value = 7)
    result : Result = ..ok Borrowing(.reference = $&target.value)
    payload ::= copy(.self = &result..ok)

    deinit(.self = $&target)
    observed ::= read(.pointer = payload.reference)
    if observed == 7 { status_code = 0 } else { status_code = 1 }
}
