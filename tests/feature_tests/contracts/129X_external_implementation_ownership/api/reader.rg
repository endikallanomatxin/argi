Reader#(.T: Type): Contract = (
    .Result: Type
    .read: (.value: &T) -> (.result: Result)
)
