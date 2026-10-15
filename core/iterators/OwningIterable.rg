-- The iterator owns undelivered values and cleans them on lexical scope exit.
OwningIterable#(.Collection: Type): Contract = (
    .Item : Type
    .IteratorType       : Type
    .to_owning_iterator : (.value: Collection) -> (.iterator: IteratorType)
)
