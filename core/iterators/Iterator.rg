Iterator#(.t: Type): Contract = (
    has_next(.self: &Self) -> (.ok: Bool)
    next(.self: $&Self) -> (.value: t)
)
