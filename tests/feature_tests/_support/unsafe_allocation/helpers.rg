-- Test-only raw storage access. Callers deliberately establish references
-- while exercising Safety's lifetime and opaque-storage transitions; they
-- remain responsible for bounds and initialization.
trusted_allocation_byte_ro(.allocation: &Allocation, .offset: UIntNative) -> (.reference: &UInt8) := {
    slot ::= raw_pointer#(.t: UInt8)(.address = allocation&.data.address + offset).raw
    mutable ::= trusted_establish_allocation_slot#(.t: UInt8)(.allocation = allocation, .slot = slot, .anchor = allocation&.anchor).reference
    reference = read_reference#(.t: UInt8)(.base = mutable).reference
}

trusted_allocation_byte_rw(.allocation: $&Allocation, .offset: UIntNative) -> (.reference: $&UInt8) := {
    slot ::= raw_pointer#(.t: UInt8)(.address = allocation&.data.address + offset).raw
    reference = trusted_establish_allocation_slot#(.t: UInt8)(.allocation = allocation, .slot = slot, .anchor = allocation&.anchor).reference
}
