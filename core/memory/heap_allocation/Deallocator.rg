-- One release request carries the original address and bounds, even when the
-- owning Allocation exposes a smaller usable prefix.
Deallocation := (
    ._data: RawPointer#(UInt8)
    ._size: UIntNative
    ._alignment: UIntNative
)

implement Deinit#(Deallocation) (
    .deinit = (.self: $&Deallocation) -> () {}
)

deallocation_layout := (.request: &Deallocation) -> (
    .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative
) {
    data = request&._data
    size = request&._size
    alignment = request&._alignment
}

-- Foreign callers can supply bounds only under the same explicit trust
-- boundary as constructing or freeing storage through the native allocator.
trusted_deallocation_request := (
    .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative,
    .ffi: $&ForeignFunctionInterface
) -> (.request: Deallocation) {
    request = (._data = data, ._size = size, ._alignment = alignment)
}

Deallocator#(.Receiver: Type): Contract = (
    .deallocate: (.self: Receiver, .request: Deallocation) -> () where {}
)
