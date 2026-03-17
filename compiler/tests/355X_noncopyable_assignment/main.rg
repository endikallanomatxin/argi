Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

main() -> (.status_code: Int32) := {
    first := Resource()
    second := first
    _ = second
    status_code = 0
}
