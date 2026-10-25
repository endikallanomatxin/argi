Resource: Type = (.id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main() -> (.status_code: Int32 = 0) := {
    owner :: Resource = Resource(.id = 1)
    original := $&owner
    active := original
    active&= Resource(.id = 2)
    status_code = original&.id
}
