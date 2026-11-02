Iterable#(.Collection: Type): Contract = (
    .Item         : Type
    .IteratorType : Type
    .to_iterator  : (.value: &Collection) -> (.iterator: IteratorType)
)

ReferenceIterable#(.Collection: Type): Contract = (
    .Item                  : Type
    .IteratorType          : Type
    .to_reference_iterator : (.value: &Collection) -> (.iterator: IteratorType)
)

MutableReferenceIterable#(.Collection: Type): Contract = (
    .Item         : Type
    .IteratorType : Type
    .to_mutable_reference_iterator : (.value: $&Collection) -> (.iterator: IteratorType)
)
