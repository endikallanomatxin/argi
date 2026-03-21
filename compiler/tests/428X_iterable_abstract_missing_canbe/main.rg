FakeIterator : Type = (
    .index: UIntNative
)

FakeIterable : Type = ()

to_iterator(.value: &FakeIterable) -> (.iterator: FakeIterator) := {
    iterator = (.index = 0)
}

sum_iterable(.items: &Iterable#(.t: Int32)) -> (.sum: Int32) := {
    iterator ::= to_iterator(.value = items)
    sum = 0
}

main () -> (.status_code: Int32) := {
    fake :: FakeIterable = ()
    status_code = sum_iterable(.items = &fake).sum
}
