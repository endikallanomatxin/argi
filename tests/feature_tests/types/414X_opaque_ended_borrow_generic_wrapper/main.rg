store := #(.T: Type) (.array: $&DynamicArray#(T), .value: T) -> () {
    push_assume_capacity(.self = array, .value = ~value)
}
Box := (.value: Int32)
implement Deinit#(Box) (
    .deinit = (.self: $&Box) -> () {}
)
main := (.system: System) -> () {
    allocator_provider ::= CAllocator(.ffi = system.ffi)
    assume allocator ::= to_virtual#(Allocator)($&allocator_provider)
    box ::= Box(42)
    reference ::= &box.value
    deinit(.self = $&box)
    array ::= unwrap_or_abort(.value = DynamicArray#(&Int32)(.capacity = 1))
    store#(&Int32)(.array = $&array, .value = reference)
    borrowed ::= unwrap_or_abort(.value = get_reference(.self = &array, .index = 0))
    if borrowed&& != 42 { abort }
}
