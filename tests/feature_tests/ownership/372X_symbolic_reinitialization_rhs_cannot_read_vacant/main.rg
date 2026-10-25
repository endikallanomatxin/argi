Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

cycle(.target: $&Resource) -> () := {
    deinit(.self = target)
    target&= Resource(.value = target&.value)
}

main() -> () := {
    owner :: Resource = Resource(.value = 1)
    cycle(.target = $&owner)
}
