Resource : Type = ()

Resource init() -> (.result: Resource) := {
    result = ()
}

deinit(.res: $&Resource) -> () := {}

main() -> (.status_code: Int32) := {
    first := Resource()
    second := first
    _ = second
    status_code = 0
}
