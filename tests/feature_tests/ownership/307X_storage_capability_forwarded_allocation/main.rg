allocation(.address: UIntNative, .deallocator: Virtual#(.abstract: Deallocator)) -> (.allocation: Allocation) := {
    allocation = establish_allocation(.storage = address, .size = 8, .alignment = 1, .deallocator = deallocator).allocation
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    address ::= malloc(.size = 8, .ffi = system.ffi).address
    backing :: CAllocator = (.ffi = system.ffi)
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = $&backing)
    first ::= allocation(.address = address, .deallocator = deallocator).allocation
    second ::= allocation(.address = address, .deallocator = deallocator).allocation
}
