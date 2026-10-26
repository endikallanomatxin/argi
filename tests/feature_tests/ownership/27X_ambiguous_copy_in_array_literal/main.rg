Resource: Type = ()

implement Init<Resource, ()> (
    .Result : Type = Resource
    .init   = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {

    }
)

_ordinary_copy_0 := (.self: &Resource, .tag: Int32 = 1) -> (.value: Resource) {
    value = Resource()
}

_ordinary_copy_1 := (.self: &Resource, .flag: Bool = true) -> (.value: Resource) {
    value = Resource()
}

main := () -> (.status_code: Int32) {
    source := Resource()
    values: [2]Resource = (source, source)
    status_code = 0
}
