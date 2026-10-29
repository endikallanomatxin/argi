NoopDeallocator: Type = ()

NoopDeallocatorInitArgs: Type = ()

implement Init#(NoopDeallocator, NoopDeallocatorInitArgs) (
    .Result : Type = NoopDeallocator

    .init = NoopDeallocatorInitArgs -> (.result: Result) {
        result = ()
    }
)

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    noop :: NoopDeallocator = NoopDeallocator()
    deallocator :: Virtual#(Deallocator) = to_virtual#(.contract: Deallocator)(
        .value = $&noop
    )
    byte :: UInt8 = 7
    Deallocator#(
    ).deallocate(
        .self = $&deallocator
        .data = raw_pointer#(.t: UInt8)(
            .address = [$&byte | convert#(.to: UIntNative)(_)]
        ).raw
        .size      = 1
        .alignment = 1
    )
    status_code = 0
}

implement Deallocator#(NoopDeallocator) (
    .deallocate = (
        .self      : $&NoopDeallocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
    }
)
