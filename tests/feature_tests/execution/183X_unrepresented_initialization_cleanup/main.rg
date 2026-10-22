Resource: Type = (.value: Int32)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

maybe_initialize(.target: $&Resource, .enabled: Bool) -> () := {
    if enabled { target&= Resource(.value = 9) }
}

main() -> (.status_code: Int32) := {
    value :: Resource = Resource(.value = 1)
    deinit(.self = $&value)
    maybe_initialize(.target = $&value, .enabled = true)
    status_code = 42
}
