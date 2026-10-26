Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

compute := () -> (.value: Int32 = 2) {
    owner :: Resource = Resource(.value = 1)
    deinit(.self = $&owner)
    deinit(.self = $&owner)
}

result := <.n: Int32> () -> (.value: Int32 = n) {}

main := () -> (.status_code: Int32 = 0) {
    status_code = result<.n = #run () -> (.value: Int32) { value = compute() }>()
}
