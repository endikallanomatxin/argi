Deallocator#(.Receiver: Type): Contract = (
    ._deallocate : (
        .self      : Receiver,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () where {}
)

-- Invoke a low-level provider on externally supplied bounds. The caller
-- vouches for the block's validity, custody and match with this provider.
trusted_deallocate_raw := (
    .provider: Virtual#(Deallocator), .data: RawPointer#(UInt8),
    .size: UIntNative, .alignment: UIntNative, .ffi: $&ForeignFunctionInterface
) -> () {
    provider._deallocate(.data = data, .size = size, .alignment = alignment)
}
