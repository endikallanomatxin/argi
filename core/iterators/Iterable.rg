Iterable#(.t: Type) : Abstract = (
    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)

ROPointerIterable#(.t: Type) : Abstract = (
    to_ro_pointer_iterator(.value: &Self) -> (.iterator: Iterator#(.t: &t))
)

RWPointerIterable#(.t: Type) : Abstract = (
    to_rw_pointer_iterator(.value: $&Self) -> (.iterator: Iterator#(.t: $&t))
)
