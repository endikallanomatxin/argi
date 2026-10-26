Iterator<.State: Type>: Contract = (
    .Item     : Type
    .has_next : (.self: &State) -> (.ok: Bool)
    .next     : (.self: $&State) -> (.value: Item)
)
