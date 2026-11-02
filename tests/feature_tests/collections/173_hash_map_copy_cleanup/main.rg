SweepAllocator := (
    .ffi: $&ForeignFunctionInterface
    .fail_at: Int32
    .attempts: Int32 = 0
    .live: Int32 = 0
)

implement Allocator#(SweepAllocator) (
    .allocate = (.self: $&SweepAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result: Errable#(Allocation, (..out_of_memory))
    ) {
        self&.attempts = self&.attempts + 1
        if self&.attempts == self&.fail_at {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        self&.live = self&.live + 1
        deallocator :: Virtual#(Deallocator) = to_virtual#(.contract: Deallocator)(.value = self)
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator#(SweepAllocator) (
    .deallocate = (.self: $&SweepAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
        self&.live = self&.live - 1
        address :: UIntNative = data.address
        free(.address = address, .ffi = self&.ffi)
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator := to_virtual#(Allocator)($&allocator_storage)
    source ::= unwrap_or_abort(HashMap#(.key: String, .value: String, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy()
    ))
    defer deinit($&source)
    first_key ::= unwrap_or_abort(format(.value = "first"))
    first_value ::= unwrap_or_abort(format(.value = "one"))
    unwrap_or_abort(put($&source, .key = ~first_key, .value = ~first_value))
    second_key ::= unwrap_or_abort(format(.value = "second"))
    second_value ::= unwrap_or_abort(format(.value = "two"))
    unwrap_or_abort(put($&source, .key = ~second_key, .value = ~second_value))

    fail_at :: Int32 = 1
    saw_success ::= false
    while fail_at <= 32 {
        failing ::= SweepAllocator(.ffi = system.ffi, .fail_at = fail_at)
        failing_virtual ::= to_virtual#(Allocator)($&failing)
        outcome ::= copy(.self = &source, .allocator = failing_virtual)
        match outcome {
            ..ok ~map {
                if contains(&map, .key = "first").ok == false { abort }
                if contains(&map, .key = "second").ok == false { abort }
                deinit($&map)
                saw_success = true
            }
            ..error error { if error.reason != ..out_of_memory { abort } }
        }
        if failing.live != 0 { abort }
        if contains(&source, .key = "first").ok == false { abort }
        if contains(&source, .key = "second").ok == false { abort }
        if saw_success { break }
        fail_at = fail_at + 1
    }
    if saw_success == false { abort }
}
