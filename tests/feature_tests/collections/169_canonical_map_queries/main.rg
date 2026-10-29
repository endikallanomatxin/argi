drops :: Int32 = 0

Part := (.id: Int32)

implement Deinit#(Part) (
    .deinit = (.self: $&Part) -> () { drops = drops + 1 }
)

Key := (.part: Part, .metadata: Int32)

Policy: Type = ()

implement HashPolicy#(Policy, Key) (
    .Query : Type = Int32
    .query = (.self: &Policy, .key: &Key) -> (.query: Int32) { query = key&.part.id }
    .hash  = (.self: &Policy, .key: Int32) -> (.hash: UIntNative) { hash = 1 }
    .equal = (.self: &Policy, .left: Int32, .right: Int32) -> (.ok: Bool) {
        ok = left == right
    }
)

lookup := #(.Map: Type: MapLookup#(.Query: Int32, .Value: Int32)) (
    .self: &Map, .key: Int32, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: ?&Int32) {
    assume error_tracer
    result = MapLookup#(Map).get_reference(self, .key = key)
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Key, .value: Int32)(.policy = Policy())!!!
    put($&map, .key = Key(.part = Part(.id = 7), .metadata = 10), .value = 40)!!!
    put($&map, .key = Key(.part = Part(.id = 8), .metadata = 20), .value = 50)!!!
    match get_mutable_reference($&map, .key = 7).result {
        ..none { abort }
        ..some found { found.value&= 42 }
    }
    match lookup(&map, .key = 7).result {
        ..none { abort }
        ..some found { if found.value&!= 42 { abort } }
    }
    match get(&map, .key = 8).result {
        ..none { abort }
        ..some found { if found.value != 50 { abort } }
    }
    if contains(&map, .key = 9).ok { abort }
    taken ::= extract($&map, .key = 7).result
    if remove($&map, .key = 8).removed == false { abort }
    if drops != 1 { abort }
    deinit($&map)
    match taken {
        ..none { abort }
        ..some ~found {
            entry ::= ~found.value
            if entry.key.metadata != 10 or entry.value != 42 { abort }
        }
    }
    if drops != 2 { abort }
    set ::= HashSet#(.key: Key)(.policy = Policy())!!!
    insert($&set, .key = Key(.part = Part(.id = 3), .metadata = 30))!!!
    if insert($&set, .key = Key(.part = Part(.id = 3), .metadata = 99))!!! { abort }
    if drops != 3 or contains(&set, .key = 3).ok == false { abort }
    if remove($&set, .key = 3).removed == false { abort }
    if drops != 4 { abort }
    text ::= HashMap#(.key: String, .value: Int32)()!!!
    put($&text, .key = format(.value = "café")!!!, .value = 99)!!!
    if contains(&text, .key = "café").ok == false { abort }
    match get(&text, .key = "café").result {
        ..none { abort }
        ..some found { if found.value != 99 { abort } }
    }
    if remove($&text, .key = "café").removed == false { abort }
    strings ::= HashSet#(.key: String)()!!!
    insert($&strings, .key = format(.value = "hello")!!!)!!!
    if contains(&strings, .key = "hello").ok == false { abort }
    match extract($&strings, .key = "hello").result {
        ..none { abort }
        ..some ~found {
            owned ::= ~found.value
            if equals(.left = view(&owned), .right = "hello").ok == false { abort }
        }
    }
    status_code = 0
}
