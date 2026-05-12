Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resources :: [2]Resource = (Resource(), Resource())
    copied := resources
    status_code = 0
}
