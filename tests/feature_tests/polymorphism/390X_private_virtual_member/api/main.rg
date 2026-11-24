Reader#(.R: Type): Contract = (
    ._read: (.receiver: R) -> (.value: Int32) where reads(receiver)
)
