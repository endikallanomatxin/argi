drops :: Int32 = 0

Tracked := (.id: Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () { drops = drops + 1 }
)

Key := (.first: Tracked, .second: Tracked)

Policy: Type = ()

implement HashPolicy#(Policy, Key) (
    .Query : Type = &Key
    .query = (.self: &Policy, .key: &Key) -> (.query: Query) { query = key }

    .hash  = (.self: &Policy, .key: &Key) -> (.hash: UIntNative) { hash = 1 }
    .equal = (.self: &Policy, .left: &Key, .right: &Key) -> (.ok: Bool) {
        ok = left&.first.id == right&.first.id
    }
)

Refusal: Type = ()

implement Allocator#(Refusal) (
    .allocate = (.self: $&Refusal, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) { result = ..error(.reason = ..out_of_memory) }
)

main := () -> (.status_code: Int32 = 1) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= CAllocator(.ffi = ffi)
    assume allocator ::= $&allocator_storage
    simple ::= unwrap_or_abort(.value = HashSet#(.key: Int32)())
    unwrap_or_abort(.value = insert($&simple, .key = 3))
    if unwrap_or_abort(.value = insert($&simple, .key = 3)) { abort }
    if contains(&simple, .key = &3).ok == false { abort }
    for item in simple { if item != 3 { abort } }
    for &item in simple { if item&!= 3 { abort } }
    custom ::= unwrap_or_abort(.value = HashSet#(.key: Key)(.policy = Policy()))
    index :: Int32 = 0
    while index < 4 {
        unwrap_or_abort(
            .value = insert(
                $&custom, .key = Key(.first = Tracked(.id = index), .second = Tracked(.id = 10))
            )
        )
        index = index + 1
    }
    if drops != 0 { abort }
    if unwrap_or_abort(
        .value = insert(
            $&custom, .key = Key(.first = Tracked(.id = 0), .second = Tracked(.id = 20))
        )
    ) {
        abort
    }
    if drops != 2 { abort }
    refusal ::= Refusal()
    match insert(
        $&custom
        .key       = Key(.first = Tracked(.id = 9), .second = Tracked(.id = 90))
        .allocator = $&refusal
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 4 or length(&custom).count != 4 { abort }
    for &item in custom { if item&.second.id != 10 { abort } }
    query ::= Key(.first = Tracked(.id = 1), .second = Tracked(.id = 0))
    taken ::= extract($&custom, .key = &query).result
    unwrap_or_abort(.value = reserve($&custom, .capacity = 32))
    deinit($&custom)
    if drops != 10 { abort }
    match taken {
        ..none { abort }
        ..some ~payload {
            key ::= ~payload.value
            if key.first.id != 1 or key.second.id != 10 { abort }
        }
    }
    if drops != 12 { abort }
    status_code = 0
}
