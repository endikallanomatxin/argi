Iterable#(.Collection: Type): Contract = (
    .Item: Type
    .IteratorType: Type
    .to_iterator: (.value: &Collection) -> (.iterator: IteratorType)
)
ROPointerIterable#(.Collection: Type): Contract = (
    .Item: Type
    .IteratorType: Type
    .to_ro_pointer_iterator: (.value: &Collection) -> (.iterator: IteratorType)
)
RWPointerIterable#(.Collection: Type): Contract = (
    .Item: Type
    .IteratorType: Type
    .to_rw_pointer_iterator: (.value: $&Collection) -> (.iterator: IteratorType)
)
