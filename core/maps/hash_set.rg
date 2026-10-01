_HashSetValue : Type = ()
_HashSetValue implements ImplicitlyCopyable

-- Membership uses the map's collision handling, storage, and key lifetimes.
HashSet#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key)) : Type = (
    ._map: HashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

init#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.p: $&HashSet#(.key: key, .policy: policy), .policy: policy, .allocator: $&Allocator, .capacity: UIntNative = 8) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    map ::= HashMap#(.key: key, .value: _HashSetValue, .policy: policy)(.policy = ~policy, .allocator = allocator, .capacity = capacity)!
    p& = (._map = ~map)
    result = ..ok Void()
}

insert#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashSet#(.key: key, .policy: policy), .key: key, .allocator: $&Allocator) -> (.result: Errable#(.t: Bool, .reasons: (..out_of_memory))) := {
    if contains(.self = &self&._map, .key = key).ok {
        result = ..ok false
        return
    }
    put(.self = $&self&._map, .key = key, .value = _HashSetValue(), .allocator = allocator)!
    result = ..ok true
}

contains#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashSet#(.key: key, .policy: policy), .key: key) -> (.ok: Bool) := {
    ok = contains(.self = &self&._map, .key = key).ok
}

remove#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashSet#(.key: key, .policy: policy), .key: key, .allocator: $&Allocator) -> (.removed: Bool) := {
    removed = remove(.self = $&self&._map, .key = key, .allocator = allocator).removed
}

length#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashSet#(.key: key, .policy: policy)) -> (.count: UIntNative) := { count = length(.self = &self&._map).count }
capacity#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &HashSet#(.key: key, .policy: policy)) -> (.count: UIntNative) := { count = capacity(.self = &self&._map).count }

deinit#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: $&HashSet#(.key: key, .policy: policy), .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&._map, .allocator = allocator)
}
