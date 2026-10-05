OwnedHashSet#(.key: Type, .policy: Type: BorrowedHashPolicy#(.key: key)): Type = (
    ._map : OwnedHashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

OwnedHashSet init#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .policy    : policy,
        .allocator : $&Allocator,
        .capacity  : UIntNative   = 8
    ) -> (
        .result : Errable#(
            .t       : OwnedHashSet#(.key: key, .policy: policy),
            .reasons : (..out_of_memory)
        )
    ) := {
    assume allocator
    constructed :: OwnedHashSet#(.key: key, .policy: policy)
    map ::= OwnedHashMap#(.key: key, .value: _HashSetValue, .policy: policy)(
        .policy    = ~policy
        .allocator = allocator
        .capacity  = capacity
    )!
    constructed = (._map = ~map)

    result = ..ok ~constructed
}

insert#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashSet#(.key: key, .policy: policy),
        .key       : key,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(.t: Bool, .reasons: (..out_of_memory))
    ) := {
    if contains(.self = &self&._map, .key = &key).ok {
        _owned_hash_discard(.value = ~key, .allocator = allocator)
        result = ..ok false
        return
    }

    put(.self = $&self&._map, .key = ~key, .value = _HashSetValue(), .allocator = allocator)!

    result = ..ok true
}

contains#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashSet#(.key: key, .policy: policy),
        .key  : &key
    ) -> (
        .ok : Bool
    ) := { ok = contains(.self = &self&._map, .key = key).ok }

remove#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashSet#(.key: key, .policy: policy),
        .key       : &key,
        .allocator : $&Allocator
    ) -> (
        .removed : Bool
    ) := { removed = remove(.self = $&self&._map, .key = key, .allocator = allocator).removed }

extract#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : $&OwnedHashSet#(.key: key, .policy: policy),
        .key  : &key
    ) -> (
        .result : ?key
    ) := {
    match extract(.self = $&self&._map, .key = key).result {
        ..none { result = ..none }
        ..some ~payload {
            entry ::= ~payload.value
            result = ..some(.value = ~entry.key)
        }
    }
}

length#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashSet#(.key: key, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = length(&self&._map).count }

capacity#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashSet#(.key: key, .policy: policy)
    ) -> (
        .count : UIntNative
    ) := { count = capacity(.self = &self&._map).count }

reserve#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashSet#(.key: key, .policy: policy),
        .capacity  : UIntNative,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_memory))
    ) := {
    result = reserve(.self = $&self&._map, .capacity = capacity, .allocator = allocator)
}

OwnedHashSet deinit#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self      : $&OwnedHashSet#(.key: key, .policy: policy),
        .allocator : $&Allocator
    ) -> () := { deinit(.self = $&self&._map, .allocator = allocator) }
