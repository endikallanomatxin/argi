FakeIterator := #(.T: Type) (.value: T)

FakeIterable := #(.T: Type) (.value: T)

main := () -> (.status_code: Int32) {
    fake: FakeIterable#(Int32) = (.value = 0)
    for value in fake {
        status_code = value
    }
    status_code = 0
}

implement#(.T: Type) Iterable#(FakeIterable#(T)) (
    .Item         : Type = T
    .IteratorType : Type = FakeIterator#(T)

    .to_iterator = (.value: &FakeIterable#(T)) -> (.iterator: FakeIterator#(T)) {
        iterator = (.value = value&.value)
    }
)
