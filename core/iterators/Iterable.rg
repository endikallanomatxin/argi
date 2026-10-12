Iterable: Contract = (
    .t: Type

    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)

ROPointerIterable: Contract = (
    .t: Type

    to_ro_pointer_iterator(.value: &Self) -> (.iterator: Iterator#(.t: &t))
)

RWPointerIterable: Contract = (
    .t: Type

    to_rw_pointer_iterator(.value: $&Self) -> (.iterator: Iterator#(.t: $&t))
)
