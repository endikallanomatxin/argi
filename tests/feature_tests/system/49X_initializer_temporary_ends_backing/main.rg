BackingAllocator: Type = (
    .page : $&PageAllocator
)

BackingAllocator deinit(.self: $&BackingAllocator) -> () := {}

EndBacking: Type = (
    .marker : Bool
)

implement Init#(EndBacking, (.backing: $&BackingAllocator)) (
    .Result: Type = EndBacking
    .init = (.args: (.backing: $&BackingAllocator)) -> (.result: Result) {
        backing ::= ~args.backing

        result = (.marker = false)
        deinit(.self = backing)
    }
)

consume(.value: EndBacking) -> () := {}

main(.system: System) -> (.status_code: Int32) := {
    backing ::= BackingAllocator(.page = system.page_allocator)
    allocator ::= GeneralPurposeAllocator(.allocator = $&backing)
    consume(.value = EndBacking(.backing = $&backing))
    result ::= allocate_bytes(.self = $&allocator, .size = 8)
    status_code = 0
}

implement Allocator#(BackingAllocator)(
    .allocate = (
            .self      : $&BackingAllocator,
            .size      : UIntNative,
            .alignment : UIntNative
        ) -> (
            .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
        ) {
        result = allocate_bytes(.self = self&.page, .size = size, .alignment = alignment)
    }
)
