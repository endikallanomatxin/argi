Resource := (.value: Int32)

References := (.left: $&Resource, .right: $&Resource)

Access := (.pair: References, .marker: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        if self&.value < 0 { abort }
        self&.value = -1
    }
)

cycle := (.args: Access) -> () {
    deinit(.self = args.pair.left)
    args.pair.left&= Resource(.value = 42)
    if args.pair.left&.value != args.marker { abort }
    deinit(.self = args.pair.left)
}

main := () -> (.status_code: Int32 = 0) {
    {
        left :: Resource = Resource(.value = 1)
        right :: Resource = Resource(.value = 2)
        cycle(.args = (.pair = (.left = $&left, .right = $&right), .marker = 42))
    }
    status_code = 42
}
