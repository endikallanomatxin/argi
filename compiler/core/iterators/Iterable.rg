Iterable#(.t: Type) : Abstract = (
    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)
