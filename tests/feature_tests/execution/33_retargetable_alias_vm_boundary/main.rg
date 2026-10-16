Resource: Type = (.id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main() -> () := {
    first :: Resource = Resource(.id = 1)
    second :: Resource = Resource(.id = 2)
    target :: $&Resource = $&first
    target = $&second
    target&= Resource(.id = 3)
}
