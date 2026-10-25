Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

copy_resource(.value: Resource) -> (.result: Resource = value) := {}

main() -> (.status_code: Int32 = 0) := {
    result := copy_resource(.value = Resource(.value = 42))
    status_code = result.value
}
