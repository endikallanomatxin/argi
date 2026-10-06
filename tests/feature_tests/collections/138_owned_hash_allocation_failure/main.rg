RecordingAllocator: Type = (
    .ffi           : $&ForeignFunctionInterface
    .fail_at       : UIntNative                 = 0
    .attempts      : UIntNative                 = 0
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
)

allocate(
        .self      : $&RecordingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative            = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := {
    self&.attempts = self&.attempts + 1
    if self&.attempts == self&.fail_at {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    self&.allocations = self&.allocations + 1
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    if UIntNative(.value = storage) == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(
        .value = self
    )
    allocation ::= trusted_establish_allocation(
        .storage     = storage
        .size        = size
        .alignment   = alignment
        .deallocator = deallocator
    )
    result = ..ok ~allocation
}

deallocate(
        .self      : $&RecordingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}

RecordingAllocator implements Allocator
RecordingAllocator implements Deallocator

Tracked: Type = (.id: Int32)

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

Policy: Type = ()

policy_drops :: UIntNative = 0

Policy deinit(.self: $&Policy) -> () := { policy_drops = policy_drops + 1 }

Policy implements BorrowedHashPolicy#(.key: Int32)

hash(.self: &Policy, .key: &Int32) -> (.hash: UIntNative) := { hash = 0 }

eql(.self: &Policy, .left: &Int32, .right: &Int32) -> (.ok: Bool) := { ok = left&== right&}

run_main(.system: System) -> !Void = ..ok Void() := {
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    map ::= OwnedHashMap#(.key: Int32, .value: Tracked, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = $&allocator
    )!
    index :: Int32 = 0
    while index < 4 {
        put(.self = $&map, .key = index, .value = Tracked(.id = index), .allocator = $&allocator)!
        index = index + 1
    }
    query :: Int32 = 0
    allocator.fail_at = allocator.attempts + 1
    match put(.self = $&map, .key = 4, .value = Tracked(.id = 4), .allocator = $&allocator) {
        ..ok _ { abort } ..error _ {}
    }
    if drops != 1 or length(.self = &map).count != 4 or capacity(.self = &map).count != 8 { abort }
    match get_ro_ref(.self = &map, .key = &query).result {
        ..none { abort } ..some payload { if [
                payload.value&.id
                != 0
            ] { abort } }
    }
    allocator.fail_at = allocator.attempts + 2
    match put(.self = $&map, .key = 4, .value = Tracked(.id = 5), .allocator = $&allocator) {
        ..ok _ { abort } ..error _ {}
    }
    if drops != 2 or length(.self = &map).count != 4 or capacity(.self = &map).count != 8 { abort }
    allocator.fail_at = 0
    put(.self = $&map, .key = 4, .value = Tracked(.id = 6), .allocator = $&allocator)!
    if drops != 2 or length(.self = &map).count != 5 { abort }
    deinit(.self = $&map, .allocator = $&allocator)
    if drops != 7 or allocator.allocations != allocator.deallocations { abort }
    allocator.fail_at = allocator.attempts + 2
    match OwnedHashMap#(.key: Int32, .value: Tracked, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = $&allocator
    ) { ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        } ..error _ {} }
    if allocator.allocations != allocator.deallocations { abort }
    allocator.fail_at = allocator.attempts + 1
    match OwnedHashMap#(.key: Int32, .value: Tracked, .policy: Policy)(
        .policy    = Policy()
        .allocator = $&allocator
    ) { ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        } ..error _ {} }
    if policy_drops != 1 { abort }
    allocator.fail_at = allocator.attempts + 2
    match OwnedHashMap#(.key: Int32, .value: Tracked, .policy: Policy)(
        .policy    = Policy()
        .allocator = $&allocator
    ) { ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        } ..error _ {} }
    if policy_drops != 2 or allocator.allocations != allocator.deallocations { abort }

}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
