Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main := () -> () {
    resources :: [2]Resource = (Resource(41), Resource(42))
    old ::= &resources[0]
    deinit(.self = $&resources[0])
    value ::= old&.value
}
