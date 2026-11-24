Deallocator#(.Receiver: Type): Contract = (
    .deallocate : (
        .self      : Receiver,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () where {}
)
