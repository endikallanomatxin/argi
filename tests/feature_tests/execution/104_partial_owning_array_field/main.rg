Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

main := () -> () {
    owners :: [2]Resource
    owners[0].value = 42
}
