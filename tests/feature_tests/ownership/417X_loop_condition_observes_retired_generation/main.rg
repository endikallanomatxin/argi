Resource := (.value: Int32)
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.value = 0 }
)
main := () -> (.status_code: Int32 = 0) {
    old :: Resource = Resource(17)
    saved ::= &old
    index :: Int32 = 0
    while [saved&.value == 17] and [index < 2] {
        deinit(.self = $&old)
        old = Resource(17)
        index = index + 1
        continue
    }
}
