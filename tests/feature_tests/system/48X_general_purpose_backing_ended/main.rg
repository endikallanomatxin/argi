BackingAllocator := (
    .page : $&PageAllocator
)

implement Deinit#(BackingAllocator) (
    .deinit = (.self: $&BackingAllocator) -> () {

    }
)

main := (.system: System) -> (.status_code: Int32) {
    backing ::= BackingAllocator(.page = system.page_allocator)
    allocator ::= GeneralPurposeAllocator(.allocator = $&backing)
    deinit(.self = $&backing)
    result ::= allocate_bytes(.self = $&allocator, .size = 8)
    status_code = 0
}

implement Allocator#(BackingAllocator) (
    .allocate = (
        .self         : $&BackingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
        assume error_tracer

        result = allocate_bytes(.self = self&.page, .size = size, .alignment = alignment)
    }
)
