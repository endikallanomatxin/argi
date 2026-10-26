FakeIterator := (
    .index : UIntNative
)

FakeIterable: Type = ()

has_next := (.self: &FakeIterator) -> (.ok: Bool) {
    ok = 0 == 1
}

next := (.self: $&FakeIterator) -> (.value: Int32) {
    value = 0
}

main := () -> (.status_code: Int32) {
    fake :: FakeIterable = ()
    for value in fake {
        status_code = value
    }
    status_code = 0
}

implement Iterable<FakeIterable> (
    .Item         : Type = Int32
    .IteratorType : Type = FakeIterator

    .to_iterator = (.value: &FakeIterable) -> (.iterator: FakeIterator) {
        iterator = (.index = 0)
    }
)
