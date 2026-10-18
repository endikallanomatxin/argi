Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

consume(.target: $&Resource) -> (.result: Int32 = 42) := {
    deinit(.self = target)
}

repeat(.target: $&Resource) -> (.result: Int32 = consume(.target = target)) := {
    deinit(.self = target)
}

main() -> (.status_code: Int32 = 0) := {
    owner :: Resource = Resource(.value = 1)
    status_code = repeat(.target = $&owner)
}
