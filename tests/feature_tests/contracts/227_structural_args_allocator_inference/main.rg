Construct#(.Target: Type, .Args: Type): Contract = (
    .Result: Type
    .construct: (.args: Args) -> (.result: Result)
)
Owner: Type = (.allocation: Allocation)
implement#(.A: Type: Allocator) Construct#(Owner, (.allocator: $&A, .length: UIntNative)) (
    .Result: Type = Errable#(Owner, (..out_of_memory))
    .construct = (.args: (.allocator: $&A, .length: UIntNative)) -> (.result: Result) {
        allocation ::= Allocator#(A).allocate(.self = args.allocator, .size = args.length, .alignment = 1)!
        result = ..ok(.allocation = ~allocation)
    }
)
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { deinit(.self = $&self&.allocation) }
)
main := (.system: System) -> (.status_code: Int32 = 0) {
    args :: (.allocator: $&PageAllocator, .length: UIntNative) = (.allocator = system.page_allocator, .length = 4)
    owner ::= unwrap_or_abort(Construct#(Owner, (.allocator: $&PageAllocator, .length: UIntNative)).construct(.args = args))
}
