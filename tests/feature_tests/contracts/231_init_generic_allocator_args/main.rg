Owner := (.allocation: Allocation)

implement<.A: Type: Allocator> Init<
    Owner, (.allocator: $&A = reach allocator, .length: UIntNative = 4)
> (
    .Result : Type = Errable<Owner, (..out_of_memory)>
    .init   = (.args: (.allocator: $&A = reach allocator, .length: UIntNative = 4)) -> (
        .result : Result
    ) {
        allocation ::= Allocator<A>.allocate(
            .self = args.allocator, .size = args.length, .alignment = 1
        )!
        result = ..ok(.allocation = ~allocation)
    }
)

implement Deinit<Owner> (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    first ::= unwrap_or_abort(Owner(.allocator = allocator, .length = 8))
    second ::= unwrap_or_abort(Owner())
    storage ::= GeneralPurposeAllocator(.allocator = allocator)
    third ::= unwrap_or_abort(Owner(.allocator = $&storage, .length = 16))
}
