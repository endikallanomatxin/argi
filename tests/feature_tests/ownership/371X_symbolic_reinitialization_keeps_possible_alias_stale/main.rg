Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

cycle(.target: $&Resource, .other: &Resource) -> () := {
    deinit(.self = target)
    target&= Resource(.value = 2)
    read := other&.value
}

main() -> () := {
    owner :: Resource = Resource(.value = 1)
    other :: Resource = Resource(.value = 2)
    cycle(.target = $&owner, .other = &other)
}
