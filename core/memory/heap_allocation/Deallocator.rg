Deallocator#(.Provider: Type): Contract = (
    .deallocate : (
        .self      : $&Provider,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () where {}
)
