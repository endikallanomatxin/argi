Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

copy(.res: Resource, .tag: Int32 = 1) -> (.out: Resource) := {
    out = Resource()
}

copy(.res: Resource, .flag: Bool = true) -> (.out: Resource) := {
    out = Resource()
}

main() -> (.status_code: Int32) := {
    source := Resource()
    copied := source
    status_code = 0
}
