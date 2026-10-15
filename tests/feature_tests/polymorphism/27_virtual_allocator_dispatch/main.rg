NoopDeallocator : Type = ()

implement Init#(NoopDeallocator, ()) (
    .Result: Type = NoopDeallocator
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

main() -> (.status_code: Int32) := {
    noop :: NoopDeallocator = NoopDeallocator()
    deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(.value = $&noop)
    byte :: UInt8 = 7
    Deallocator#().deallocate(.self = $&deallocator, .data = raw_pointer#(.t: UInt8)(.address = $&byte | convert#(.to: UIntNative)(_)).raw, .size = 1, .alignment = 1)
    status_code = 0
}

implement Deallocator#(NoopDeallocator)(
.deallocate = (.self: $&NoopDeallocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
}
)
