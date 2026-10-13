_HashSetValue: Type = ()

implement ImplicitlyCopyable#(_HashSetValue) ()

-- Membership uses the map's collision handling, storage, and key lifetimes.
HashSet#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)): Type = (
    ._map : HashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

implement#(
    .key : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key),
    .Provider: Type: Allocator
) Init#(
    HashSet#(.key: key, .policy: policy),
    (
        .policy : policy,
        .allocator : $&Provider = reach allocator,
        .capacity : UIntNative = 8,
    )
) (
    .Result: Type = Errable#(HashSet#(.key: key, .policy: policy), (..out_of_memory))
    .init = (.args: (
        .policy : policy,
        .allocator : $&Provider = reach allocator,
        .capacity : UIntNative = 8,
    )) -> (.result: Result) {
        policy ::= ~args.policy
        allocator ::= args.allocator
        capacity ::= args.capacity

        constructed :: HashSet#(.key: key, .policy: policy)

        map ::= HashMap#(.key: key, .value: _HashSetValue, .policy: policy)(
            .policy    = ~policy
            .allocator = allocator
            .capacity  = capacity
        )!
        constructed = (._map = ~map)

        result = ..ok ~constructed
    }
)

insert#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self      : $&HashSet#(.key: key, .policy: policy),
        .key       : key,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Bool, (..out_of_memory))
    ) := {
    if contains(&self&._map, .key = key).ok {
        result = ..ok false
        return
    }

    put(.self = $&self&._map, .key = key, .value = _HashSetValue(), .allocator = allocator)!

    result = ..ok true
}

contains#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self : &HashSet#(.key: key, .policy: policy),
        .key  : key
    ) -> (
        .ok : Bool
    ) := {
    ok = contains(&self&._map, .key = key).ok
}

remove#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self      : $&HashSet#(.key: key, .policy: policy),
        .key       : key,
        .allocator : $&Allocator
    ) -> (
        .removed : Bool
    ) := {
    removed = remove(.self = $&self&._map, .key = key, .allocator = allocator).removed
}

length#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self : &HashSet#(.key: key, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = length(&self&._map).count }

capacity#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    )(
        .self : &HashSet#(.key: key, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = capacity(&self&._map).count }

implement#(
        .key    : Type: ImplicitlyCopyable,
        .policy : Type: HashPolicy#(policy, key)
    ) Deinit#(HashSet#(.key: key, .policy: policy)) (
    .deinit = (.self: $&HashSet#(.key: key, .policy: policy)) -> () {
        deinit(.self = $&self&._map)
    }
)
