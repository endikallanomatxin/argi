Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main := () -> (.status_code: Int32) {
    resource :: Resource = (.value = 42)
    values :: [1]Int32
    values[0] = depend_on#(.t: Int32)(.value = 42, .on = &resource).result
    deinit(.self = $&resource)
    status_code = values[0]
}
