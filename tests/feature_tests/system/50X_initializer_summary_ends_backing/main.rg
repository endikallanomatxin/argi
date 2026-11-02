BackingAllocator := (
    .page : Virtual#(Allocator)
)

implement Deinit#(BackingAllocator) (
    .deinit = (.self: $&BackingAllocator) -> () {

    }
)

EndBacking := (
    .marker : Bool
)

EndBackingInitArgs: Type = (.backing: $&BackingAllocator)

implement Init#(EndBacking, EndBackingInitArgs) (
    .Result : Type = EndBacking

    .init = EndBackingInitArgs -> (.result: Result) {
        _init_backing ::= ~backing

        result = (.marker = false)
        deinit(.self = _init_backing)
    }
)

consume := (.value: EndBacking) -> () {}

end_backing := (.backing: $&BackingAllocator) -> () {
    consume(.value = EndBacking(.backing = backing))
}

main := (.system: System) -> (.status_code: Int32) {

    backing ::= BackingAllocator(.page = system.page_allocator)

    backing_virtual ::= to_virtual#(Allocator)($&backing)
    allocator ::= GeneralPurposeAllocator(.allocator = backing_virtual)
    end_backing(.backing = $&backing)
    result ::= allocate_bytes(.self = $&allocator, .size = 8)
    status_code = 0
}

implement Allocator#(BackingAllocator) (
    .allocate = (.self: $&BackingAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {

        result = allocate_bytes(.self = $&self&.page, .size = size, .alignment = alignment)
    }
)
