Reader#(.T: Type): Contract = (
    .Result : Type
    ._read  : (.value: &T) -> (.result: Result)
)
