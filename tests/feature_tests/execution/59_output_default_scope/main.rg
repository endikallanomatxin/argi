Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

transfer(.value: Resource) -> (.result: Resource = ~value) := {}

increment(.value: Int32) -> (.result: Int32 = value + 1) := {}

compute(.value: Int32) -> (.first: Int32 = value | increment(_), .second: Int32 = first + 1) := {}

reference(.target: &Int32) -> (.result: &Int32 = target) := {}

main() -> (.status_code: Int32 = 0) := {
    owner := transfer(.value = Resource(.value = 40))
    value :: Int32 = owner.value
    results := compute(.value = reference(.target = &value)&)
    if results.first != 41 { abort }
    status_code = results.second
}
