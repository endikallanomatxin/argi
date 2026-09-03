NoopDeallocator : Type = ()

init(.p: $&NoopDeallocator) -> () := {
}

deallocate(.self: $&NoopDeallocator, .data: $&UInt8, .size: UIntNative) -> () := {
}

NoopDeallocator implements Deallocator

main() -> (.status_code: Int32) := {
    noop :: NoopDeallocator = NoopDeallocator()
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&noop)
    byte :: UInt8 = 7
    deallocate(.self = $&deallocator, .data = $&byte, .size = 1)
    status_code = 0
}
