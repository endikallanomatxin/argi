-- Conversion consumes the complete collection. The iterator owns any values
-- not yet delivered and releases them during ordinary lexical cleanup.
OwningIterable: Contract = (
    .t: Type

    to_owning_iterator(.value: Self) -> (.iterator: Iterator#(.t: t))
)
