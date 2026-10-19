Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main := () -> (.status_code: Int32) {
    resource :: Resource = (.value = 42)
    references :: [1]&Resource
    references[0] = &resource
    complete ::= references
    deinit(.self = $&resource)
    status_code = complete[0]&.value
}
