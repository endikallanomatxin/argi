Resource: Type = (.value: Int32)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

observe(.targets: [2] $&Resource) -> () := {
    deinit(.self = targets[0])
    if targets[1]&.value == 0 { abort }
}

main() -> (.status_code: Int32) := {
    owner :: Resource = Resource(.value = 1)
    observe(.targets = ($&owner, $&owner))
    status_code = 42
}
