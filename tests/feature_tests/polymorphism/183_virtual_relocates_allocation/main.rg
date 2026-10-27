Mover#(.Participant: Type): Contract = (
    .transfer : (
        .self: &Participant, .source: $&DynamicArray#(Int32), .destination: $&DynamicArray#(Int32)
    ) -> ()
    where relocates(destination, source)
)

Manager := (.unused: Int32)

implement Mover#(Manager) (.transfer = _impl_transfer_Manager)

_impl_transfer_Manager := (
    .self: &Manager, .source: $&DynamicArray#(Int32), .destination: $&DynamicArray#(Int32)
) -> () {
    relocate(source, destination)
}

transfer_owned := (
    .mover: &Virtual#(Mover), .source: $&DynamicArray#(Int32), .destination: $&DynamicArray#(Int32)
) -> () {
    transfer(mover, source, destination)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)

    source ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 2))
    unwrap_or_abort(push(.self = $&source, .value = 42))
    destination ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1))
    deinit(.self = $&destination)
    transfer_owned(&mover, $&source, $&destination)

    offset :: UIntNative = 0
    element ::= unwrap_or_abort(get_reference(.self = &destination, .index = offset))
    if element&!= 42 { status_code = 1 }
}
