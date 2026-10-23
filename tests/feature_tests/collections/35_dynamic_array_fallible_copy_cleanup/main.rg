Counter: Type = (.count: UIntNative = 0)

implement ErrorTracer#(Counter) (
    .add_context = (.self: $&Counter, .location: SourceLocationId, .context: StringView) -> () {
        self&.count = self&.count + 1
    }
    .reset_context = (.self: $&Counter) -> () { self&.count = 0 }
    .report        = (.self: $&Counter, .writer: $&Virtual#(.contract: Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = ..ok Void()
    }
)

FailFourthAllocator: Type = (
    .ffi : $&ForeignFunctionInterface
    .allocation_attempts : Int32
    .array_backing_size : UIntNative
    .deallocations : Int32
    .backing_freed_after_elements : Bool
)

implement Init#(FailFourthAllocator, (.ffi: $&ForeignFunctionInterface)) (
    .Result : Type = FailFourthAllocator
    .init   = (.args: (.ffi: $&ForeignFunctionInterface)) -> (.result: Result) {
        assume ffi := ~args.ffi

        result.ffi = ffi
        result.allocation_attempts = 0
        result.array_backing_size = 0
        result.deallocations = 0
        result.backing_freed_after_elements = false
    }
)

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    source ::= unwrap_or_abort(.value = DynamicArray#(.t: String)(.capacity = 3))
    #defer deinit(.self = $&source)

    first ::= unwrap_or_abort(.value = String(.length = 1))
    second ::= unwrap_or_abort(.value = String(.length = 1))
    third ::= unwrap_or_abort(.value = String(.length = 1))
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~first)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~second)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~third)

    tracer ::= Counter(.count = 7)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    failing ::= FailFourthAllocator(.ffi = system.ffi)
    copied ::= copy(.self = &source, .allocator = $&failing)
    if is(.value = copied, .variant = ..ok) {
        status_code = 1
        return
    }
    match copied {
        ..ok ~value { abort }
        ..error error { ErrorTracer#().reset_context(.self = error.tracer) }
    }
    if tracer.count != 0 {
        status_code = 4
        return
    }
    if failing.allocation_attempts != 4 or failing.deallocations != 3 {
        status_code = 2
        return
    }
    if failing.backing_freed_after_elements == false {
        status_code = 3
    }
}

implement Allocator#(FailFourthAllocator) (
    .allocate = (.self: $&FailFourthAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {
        self&.allocation_attempts = self&.allocation_attempts + 1
        if self&.allocation_attempts == 4 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        if self&.allocation_attempts == 1 { self&.array_backing_size = size }
        deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
            .value = self
        )
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator#(FailFourthAllocator) (
    .deallocate = (
        .self      : $&FailFourthAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        -- The first backing request can include typed metadata. Both completed
        -- element copies must be released before that physical block.
        if size == self&.array_backing_size {
            self&.backing_freed_after_elements = self&.deallocations == 2
        }
        self&.deallocations = self&.deallocations + 1
        address :: UIntNative = data.address
        free(.address = address, .ffi = self&.ffi)
    }
)
