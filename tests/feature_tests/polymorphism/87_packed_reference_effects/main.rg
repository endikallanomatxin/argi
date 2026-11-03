Resource := (.value: Int32)
drops :: Int32 = 0
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
)
forward := (.source: &Resource) -> (.result: &Resource) { result = source }
renew := (.target: $&Resource) -> () {
    deinit(.self = target)
    target&= Resource(42)
}

main := () -> () {
    {
        owner :: Resource = Resource(41)
        reference_args: inputs_of#(forward) = (.source = &owner)
        borrowed := invoke#(forward)(.args = ~reference_args)
        if borrowed&.value != 41 { abort }
        renew_args: inputs_of#(renew) = (.target = $&owner)
        invoke#(renew)(.args = ~renew_args)
        if owner.value != 42 { abort }
    }
    if drops != 2 { abort }
}
