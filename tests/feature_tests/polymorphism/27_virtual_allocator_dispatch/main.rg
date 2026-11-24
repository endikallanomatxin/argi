NoopDeallocator: Type = ()

NoopDeallocatorInitArgs: Type = ()

implement Init#(NoopDeallocator, NoopDeallocatorInitArgs) (
    .Result : Type = NoopDeallocator

    .init = NoopDeallocatorInitArgs -> (.result: Result) {
        result = ()
    }
)

main := (.system: System) -> (.status_code: Int32) {

    noop :: NoopDeallocator = NoopDeallocator()
    deallocator :: Virtual#(Deallocator) = Virtual#(.contract: Deallocator)(.value = $&noop)
    byte :: UInt8 = 7
    request ::= trusted_deallocation_request(
        .ffi = system.ffi
        .data = raw_pointer#(.t: UInt8)(
            .address = [$&byte | convert#(.to: UIntNative)(_)]
        ).raw
        .size      = 1
        .alignment = 1
    )
    deallocator.deallocate(.request = ~request)
    status_code = 0
}

implement Deallocator#($&NoopDeallocator) (
    .deallocate = (
        .self      : $&NoopDeallocator,
        .request: Deallocation
    ) -> () {
    }
)
