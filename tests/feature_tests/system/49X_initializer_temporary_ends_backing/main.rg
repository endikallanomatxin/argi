BackingAllocator := (
    .page : $&PageAllocator
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

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    backing ::= BackingAllocator(.page = system.page_allocator)
    allocator ::= GeneralPurposeAllocator(.allocator = $&backing)
    consume(.value = EndBacking(.backing = $&backing))
    result ::= allocate_bytes(.self = $&allocator, .size = 8)
    status_code = 0
}

implement Allocator#(BackingAllocator) (
    .allocate = (
        .self         : $&BackingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
        assume error_tracer

        result = allocate_bytes(.self = self&.page, .size = size, .alignment = alignment)
    }
)
