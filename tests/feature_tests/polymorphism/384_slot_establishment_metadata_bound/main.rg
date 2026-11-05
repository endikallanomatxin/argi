SlotReader#(.T: Type): Contract = (
    .inspect: (.self: &T, .allocation: &Allocation, .slot: RawPointer#(.t: Int32)) -> ()
        where reads(allocation)
)
Provider := (.marker: Int32)
implement SlotReader#(Provider) (
    .inspect = (.self: &Provider, .allocation: &Allocation, .slot: RawPointer#(.t: Int32)) -> () {
        _ = trusted_establish_allocation_slot#(.t: Int32)(
            .allocation = allocation, .slot = slot, .anchor = allocation&.anchor
        ).reference
    }
)
main := () -> () {
    provider ::= Provider(0)
    reader ::= to_virtual#(SlotReader)(&provider)
}
