ReleaseCounter := (.memory: $&Memory, .releases: UIntNative = 0)
FailSecond := (.release: $&ReleaseCounter, .requests: UIntNative = 0)

implement Deallocator#($&ReleaseCounter) (
    .deallocate = (.self: $&ReleaseCounter, .request: Deallocation) -> () {
        self&.releases = self&.releases + 1
        Deallocator#().deallocate(.self = self&.memory, .request = ~request)
    }
)

implement Allocator#(FailSecond) (
    .allocate = (.self: $&FailSecond, .size: UIntNative, .alignment: UIntNative) -> (
        .result: Errable#(Allocation, (..out_of_memory))
    ) {
        self&.requests = self&.requests + 1
        if self&.requests == 2 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        storage ::= unwrap_or_abort(acquire_page_storage(.memory = self&.release&.memory, .size = size, .alignment = alignment))
        receipt ::= establish_allocation(.storage = ~storage, .size = size, .alignment = alignment,
            .deallocator = Virtual#(Deallocator)(self&.release))
        result = ..ok ~receipt
    }
)

main := (.system: System) -> () {
    release: ReleaseCounter = (.memory = system.memory)
    backing: FailSecond = (.release = $&release)
    heap ::= GeneralPurposeAllocator(.allocator = Virtual#(Allocator)($&backing))
    match String(.allocator = Virtual#(Allocator)($&heap), .length = 8192) {
        ..ok ~unexpected { abort }
        ..error _ {}
    }
    if backing.requests != 2 or release.releases != 1 or has_live_allocations(&heap) { abort }
}
