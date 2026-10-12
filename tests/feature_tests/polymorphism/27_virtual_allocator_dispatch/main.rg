NoopDeallocator : Type = ()

NoopDeallocator init() -> (.result: NoopDeallocator) := {
    result = ()

}

main() -> (.status_code: Int32) := {
    noop :: NoopDeallocator = NoopDeallocator()
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&noop)
    byte :: UInt8 = 7
    Deallocator#().deallocate(.self = $&deallocator, .data = raw_pointer#(.t: UInt8)(.address = UIntNative(.value = $&byte)).raw, .size = 1, .alignment = 1)
    status_code = 0
}

implement Deallocator#(NoopDeallocator)(
.deallocate = (.self: $&NoopDeallocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
}
)
