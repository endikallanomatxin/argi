drops :: Int32 = 0

Tracked: Type = (.id: Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () { drops = drops + 1 }
)

Key: Type = (.first: Tracked, .second: Tracked)

Policy: Type = ()

implement HashPolicy#(Policy, Key) (
    .hash = (.self: &Policy, .key: &Key) -> (.hash: UIntNative) { hash = 1 }
    .eql  = (.self: &Policy, .left: &Key, .right: &Key) -> (.ok: Bool) {
        ok = left&.first.id == right&.first.id
    }
)

Refusal: Type = ()

implement Allocator#(Refusal) (
    .allocate = (.self: $&Refusal, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) { result = ..error(.reason = ..out_of_memory) }
)

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    simple ::= HashSet#(.key: Int32)()!
    insert($&simple, .key = 3)!
    if insert($&simple, .key = 3)! { abort }
    if contains(&simple, .key = &3).ok == false { abort }
    for item in simple { if item != 3 { abort } }
    for &item in simple { if item&!= 3 { abort } }
    custom ::= HashSet#(.key: Key)(.policy = Policy())!
    index :: Int32 = 0
    while index < 4 {
        insert($&custom, .key = Key(.first = Tracked(.id = index), .second = Tracked(.id = 10)))!
        index = index + 1
    }
    if drops != 0 { abort }
    if insert($&custom, .key = Key(.first = Tracked(.id = 0), .second = Tracked(.id = 20)))! {
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
    reserve($&custom, .capacity = 32)!
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
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
