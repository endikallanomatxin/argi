Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

consume(.res: Resource) -> (.status_code: Int32) := {
    status_code = 0
}

main() -> (.status_code: Int32) := {
    handle := Resource()
    status_code = consume(.res = ~handle)
}
