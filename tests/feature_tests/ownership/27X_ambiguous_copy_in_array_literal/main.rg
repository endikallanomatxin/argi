Resource : Type = ()

Resource init() -> (.result: Resource) := {
    result = ()
}

Resource deinit(.res: $&Resource) -> () := {}


copy(.self: &Resource, .tag: Int32 = 1) -> (.value: Resource) := {
    value = Resource()
}

copy(.self: &Resource, .flag: Bool = true) -> (.value: Resource) := {
    value = Resource()
}

main() -> (.status_code: Int32) := {
    source := Resource()
    values : [2]Resource = (source, source)
    status_code = 0
}
