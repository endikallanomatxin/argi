Counter := (.value: Int32)

Counting#(.State: Type): Contract = (
    .bump : (.self: $&State, .amount: Int32) -> () where {}
    .read : (.self: &State) -> (.result: Int32) where {}
)

implement Counting#(Counter) (
    .bump = (.self: $&Counter, .amount: Int32) -> () {
        self&.value = self&.value + amount
    }
    .read = (.self: &Counter) -> (.result: Int32) {
        result = self&.value
    }
)

Holder := (.counter: Virtual#(.contract: Counting), .tag: UInt8)

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    counter :: Counter = (.value = 7)
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: Holder)(.self = $&allocator))
    raw ::= raw_pointer#(.t: Holder)(.address = memory.data.address).raw
    slot ::= trusted_establish_allocation_slot#(.t: Holder)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    slot&= Holder(.counter = to_virtual#(.contract: Counting)(.value = $&counter), .tag = 1)
    slot&.tag = 2
    Counting#().bump(.self = $&slot&.counter, .amount = 35)
    if slot&.tag != 2 { abort }
    status_code = Counting#().read(.self = &slot&.counter).result
}
