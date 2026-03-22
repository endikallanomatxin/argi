Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

identity(.res: Resource) -> (.out: Resource) := {
    out = res
}

main() -> (.status_code: Int32) := {
    status_code = 0
}
