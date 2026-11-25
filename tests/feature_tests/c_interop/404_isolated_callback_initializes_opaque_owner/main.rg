Reader#(.R: Type): Contract = (
    .read: (.self: R) -> (.result: CInt) where no_access()
)
implement Reader#(&CInt) (
    .read = (.self: &CInt) -> (.result: CInt) { result = 1 }
)

Owner := (.value: CInt)
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        marker: CInt = 0
        reader ::= Virtual#(Reader)(&marker)
        if reader.read().result != self&.value { abort }
    }
)

Callback(.address: UIntNative) -> (): CFunctionPointer(.isolated = true)
publish := (.address: UIntNative) -> (): CFunction {
    anchor: UInt8 = 0
    destination ::= trusted_establish_inherited_reference#(Owner)(
        .raw = raw_pointer#(Owner)(.address = address),
        .root = erase_reference#(UInt8)(.base = &anchor)
    )
    value ::= Owner(1)
    trusted_opaque_move#(Owner)(.destination = destination, .source = ~value)
}

main := (.system: System) -> () {
    assume ffi := system.ffi
    allocator ::= CAllocator(.ffi = ffi)
    allocation ::= unwrap_or_abort(allocate_bytes(.self = $&allocator, .size = size_of(.type = Owner)))
    callback ::= Callback(.function = publish)
    callback(.address = allocation.data.address)
    slot ::= trusted_establish_allocation_slot#(Owner)(
        .allocation = &allocation, .slot = raw_pointer#(Owner)(.address = allocation.data.address),
        .anchor = allocation.anchor
    )
    if slot&.value != 1 { abort }
    trusted_opaque_drop#(Owner)(.slot = slot)
}
