Iterable#(.t: Type): contract = (
    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)

ROPointerIterable#(.t: Type): contract = (
    to_ro_pointer_iterator(.value: &Self) -> (.iterator: Iterator#(.t: &t))
)

RWPointerIterable#(.t: Type): contract = (
    to_rw_pointer_iterator(.value: $&Self) -> (.iterator: Iterator#(.t: $&t))
)
