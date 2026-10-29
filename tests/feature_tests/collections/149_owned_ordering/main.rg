drops :: Int32 = 0

Tracked := (.id: Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        drops = drops + 1
    }
)

Pair := (.a: Tracked, .b: Tracked)

PairOrder: Type = ()

implement OrderPolicy#(PairOrder, Pair) (
    .less = (.self: &PairOrder, .left: &Pair, .right: &Pair) -> (.ok: Bool) {
        ok = [left&.a.id < right&.a.id]
    }
)

RefusingAllocator: Type = ()

main := () -> (.status_code: Int32 = 1) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    storage ::= CAllocator(.ffi = ffi)
    assume allocator ::= $&storage
    order ::= PairOrder()
    items ::= [DynamicArray#(.t: Pair)(.capacity = 3) | unwrap_or_abort(_)]
    push_assume_capacity(
        .self = $&items, .value = Pair(.a = Tracked(.id = 3), .b = Tracked(.id = 30))
    )
    push_assume_capacity(
        .self = $&items, .value = Pair(.a = Tracked(.id = 1), .b = Tracked(.id = 10))
    )
    push_assume_capacity(
        .self = $&items, .value = Pair(.a = Tracked(.id = 2), .b = Tracked(.id = 20))
    )
    sort_owned(.self = $&items, .order = &order)
    if unwrap_or_abort(.value = get_reference(.self = &items, .index = 0))&.a.id != 1 { abort }
    reverse_owned(.self = $&items)
    if unwrap_or_abort(.value = get_reference(.self = &items, .index = 0))&.a.id != 3 { abort }
    if drops != 0 { abort }
    for ~item in items { if item.b.id != item.a.id * 10 { abort } }
    if drops != 6 { abort }
    queue ::= [
        PriorityQueue#(.t: Pair, .order: PairOrder)(
            .order = &order, .allocator = allocator, .capacity = 1
        )
        | unwrap_or_abort(_)
    ]
    submitted_0 ::= [
        push(
            .self      = $&queue
            .value     = Pair(.a = Tracked(.id = 3), .b = Tracked(.id = 30))
            .allocator = allocator
        )
        | unwrap_or_abort(_)
    ]
    submitted_1 ::= [
        push(
            .self      = $&queue
            .value     = Pair(.a = Tracked(.id = 1), .b = Tracked(.id = 10))
            .allocator = allocator
        )
        | unwrap_or_abort(_)
    ]
    submitted_2 ::= [
        push(
            .self      = $&queue
            .value     = Pair(.a = Tracked(.id = 2), .b = Tracked(.id = 20))
            .allocator = allocator
        )
        | unwrap_or_abort(_)
    ]
    match peek_reference(.self = &queue).value {
        ..none { abort } ..some entry { if entry.value&.a.id != 1 { abort } }
    }
    match pop(.self = $&queue).result {
        ..none { abort } ..some ~entry { if entry.value.a.id != 1 { abort } }
    }
    if drops != 8 { abort }
    deinit(.self = $&queue)
    if drops != 12 { abort }
    refusal ::= RefusingAllocator()
    bounded ::= [
        PriorityQueue#(.t: Pair, .order: PairOrder)(
            .order = &order, .allocator = allocator, .capacity = 1
        )
        | unwrap_or_abort(_)
    ]
    submitted_3 ::= [
        push(
            .self      = $&bounded
            .value     = Pair(.a = Tracked(.id = 4), .b = Tracked(.id = 40))
            .allocator = allocator
        )
        | unwrap_or_abort(_)
    ]
    match peek_reference(.self = &bounded).value {
        ..none { abort }
        ..some held {
            match push(
                .self      = $&bounded
                .value     = Pair(.a = Tracked(.id = 5), .b = Tracked(.id = 50))
                .allocator = $&refusal
            ) {
                ..ok _ { abort }
                ..error error {
                    if error.reason != ..out_of_memory or held.value&.a.id != 4 { abort }
                }
            }
        }
    }
    if drops != 14 or length(.self = &bounded).count != 1 { abort }
    match peek_reference(.self = &bounded).value {
        ..none { abort } ..some entry { if [entry.value&.a.id != 4] { abort } }
    }
    submitted_4 ::= [
        push(
            .self      = $&bounded
            .value     = Pair(.a = Tracked(.id = 5), .b = Tracked(.id = 50))
            .allocator = allocator
        )
        | unwrap_or_abort(_)
    ]
    if drops != 14 or length(.self = &bounded).count != 2 { abort }
    match peek_reference(.self = &bounded).value {
        ..none { abort } ..some entry { if [entry.value&.a.id != 4] { abort } }
    }
    deinit(.self = $&bounded)
    if drops != 18 { abort }
    status_code = 0
}

implement Allocator#(RefusingAllocator) (
    .allocate = (
        .self         : $&RefusingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative                         = 1,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
        assume error_tracer

        result = ..error(.reason = ..out_of_memory)
    }
)
