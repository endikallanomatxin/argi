Duplicate#(.T: Type): Contract = (
    .copy : (.value: &T) -> (.result: T)
    .copy : (.value: T) -> (.result: T)
)

main := () -> () {}
