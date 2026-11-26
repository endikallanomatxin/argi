Resource := (.value: Int32)
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.value = 0 }
)
propagate := (
    .destination: $&DynamicArray#(UIntNative),
    .allocator: Virtual#(Allocator)
) -> (.status_code: Int32) {
    stable :: Resource = Resource(42)
    old :: Resource = Resource(17)
    saved ::= &old
    p0 :: &Resource = &stable
    p1 :: &Resource = &stable
    p2 :: &Resource = &stable
    p3 :: &Resource = &stable
    p4 :: &Resource = &stable
    p5 :: &Resource = &stable
    p6 :: &Resource = &stable
    p7 :: &Resource = &stable
    p8 :: &Resource = &stable
    p9 :: &Resource = &stable
    p10 :: &Resource = &stable
    p11 :: &Resource = &stable
    index :: Int32 = 0
    while index < 12 {
        unwrap_or_abort(push(destination, .value = 0, .allocator = allocator))
        p11 = p10
        p10 = p9
        p9 = p8
        p8 = p7
        p7 = p6
        p6 = p5
        p5 = p4
        p4 = p3
        p3 = p2
        p2 = p1
        p1 = p0
        p0 = saved
        index = index + 1
    }
    deinit(.self = $&old)
    status_code = p11&.value
}

main := (.system: System) -> (.status_code: Int32) {
    assume allocator := system.page_allocator
    destination ::= unwrap_or_abort(DynamicArray#(UIntNative)(.allocator = allocator, .capacity = 12))
    status_code = propagate(.destination = $&destination, .allocator = allocator)
}
