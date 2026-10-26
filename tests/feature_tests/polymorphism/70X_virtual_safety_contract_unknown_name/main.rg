Source<.Participant: Type>: Contract = (
    .get : (.self: &Participant) -> (.value: &Int32)
    where depends_on(value, missing)
)

main := () -> () {}
