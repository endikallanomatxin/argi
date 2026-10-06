drops :: UIntNative = 0

Tracked: Type = (.id: Int32)

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

Pair: Type = (.first: Tracked, .second: Tracked)

_pair(.id: Int32) -> (.value: Pair) := {
    value = (.first = Tracked(.id = id), .second = Tracked(.id = id))
}

RefusingAllocator: Type = ()

RefusingAllocator implements Allocator

allocate(
        .self      : $&RefusingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative           = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := { result = ..error(.reason = ..out_of_memory) }

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    refusal ::= RefusingAllocator()
    array ::= DynamicArray#(.t: Pair)(.allocator = allocator, .capacity = 1)!
    push(.self = $&array, .value = _pair(.id = 1).value, .allocator = allocator)!
    match push(.self = $&array, .value = _pair(.id = 2).value, .allocator = $&refusal) {
        ..ok _ { abort } ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 2 { abort }
    match insert(.self = $&array, .i = 0, .value = _pair(.id = 3).value, .allocator = $&refusal) {
        ..ok _ { abort } ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 4 { abort }
    match insert(.self = $&array, .i = 9, .value = _pair(.id = 4).value, .allocator = allocator) {
        ..ok _ { abort } ..error error { if error.reason != ..out_of_bounds { abort } }
    }
    if drops != 6 { abort }
    match set(.self = $&array, .index = 9, .value = _pair(.id = 5).value, .allocator = allocator) {
        ..ok _ { abort } ..error error { if error.reason != ..out_of_bounds { abort } }
    }
    if drops != 8 { abort }
    set(.self = $&array, .index = 0, .value = _pair(.id = 6).value, .allocator = allocator)!
    if drops != 10 { abort }
    if unwrap_or_abort(.value = get_ro_ref(.self = &array, .index = 0))&.first.id != 6 { abort }
    deinit(.self = $&array, .allocator = allocator)
    if drops != 12 { abort }
    ring ::= RingBuffer#(.t: Pair)(.capacity = 2, .allocator = allocator)!
    push(.self = $&ring, .value = _pair(.id = 7).value, .allocator = allocator)!
    push(.self = $&ring, .value = _pair(.id = 8).value, .allocator = allocator)!
    match push(.self = $&ring, .value = _pair(.id = 9).value, .allocator = allocator) {
        ..ok _ { abort } ..error error { if error.reason != ..full { abort } }
    }
    if drops != 14 { abort }
    { extracted ::= ~unwrap_or_abort(.value = pop(.self = $&ring)) }
    if drops != 16 { abort }
    push(.self = $&ring, .value = _pair(.id = 10).value, .allocator = allocator)!
    deinit(.self = $&ring, .allocator = allocator)
    if drops != 20 { abort }
    deque ::= Deque#(.t: Pair)(.capacity = 1, .allocator = allocator)!
    push_back(.self = $&deque, .value = _pair(.id = 11).value, .allocator = allocator)!
    match push_front(.self = $&deque, .value = _pair(.id = 12).value, .allocator = $&refusal) {
        ..ok _ { abort } ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 22 { abort }
    match push_back(.self = $&deque, .value = _pair(.id = 13).value, .allocator = $&refusal) {
        ..ok _ { abort } ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 24 { abort }
    deinit(.self = $&deque, .allocator = allocator)
    if drops != 26 { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
