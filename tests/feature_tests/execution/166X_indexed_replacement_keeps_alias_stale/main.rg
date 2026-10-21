Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main() -> () := {
    resources :: [2]Resource = (Resource(41), Resource(42))
    old ::= &resources[0]
    resources[0] = Resource(43)
    value ::= old&.value
}
