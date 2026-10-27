Owner := (.flag: Bool)

Arguments := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)

Factory#(.Participant: Type): Contract = (
    .Args : #(.Item: Type) Type
)

implement Factory#(Owner) (
    .Args : #(.Item: Type) Type = Arguments
)

main := () -> () {}
