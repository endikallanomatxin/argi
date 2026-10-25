drops :: Int32 = 0

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
)

initialize(.target: $&Resource) -> () := { target&= Resource(.value = 2) }

cycle(.target: $&Resource) -> () := {
    deinit(.self = target)
    initialize(.target = target)
    if target&.value != 2 { abort }
    deinit(.self = target)
}

main() -> (.status_code: Int32 = 0) := {
    {
        owner :: Resource = Resource(.value = 1)
        cycle(.target = $&owner)
    }
    if drops != 2 { abort }
    status_code = 42
}
