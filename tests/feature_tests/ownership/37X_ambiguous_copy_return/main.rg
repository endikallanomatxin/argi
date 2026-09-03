Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}


copy(.self: &Resource, .tag: Int32 = 1) -> (.value: Resource) := {
    value = Resource()
}

copy(.self: &Resource, .flag: Bool = true) -> (.value: Resource) := {
    value = Resource()
}

duplicate(.source: Resource) -> (.value: Resource) := {
    return source
}

main() -> (.status_code: Int32) := {
    status_code = 0
}
