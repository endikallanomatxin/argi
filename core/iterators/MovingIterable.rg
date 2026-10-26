-- The iterator owns undelivered values and cleans them on lexical scope exit.
MovingIterable<.Collection: Type>: Contract = (
    .Item               : Type
    .IteratorType       : Type
    .to_moving_iterator : (.value: Collection) -> (.iterator: IteratorType)
)
