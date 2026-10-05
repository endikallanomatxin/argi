OwnedHashMapBorrow#(.key: Type, .value: Type): Type = (.key: &key, .value: &value)

OwnedHashMapBorrow#(.key: Type, .value: Type) implements ImplicitlyCopyable

OwnedHashMapIterator#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(.key: key)): Type = (
    ._owner      : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
    ._generation : &Any,
    ._index      : UIntNative
)

OwnedHashMapIterator#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(.key: key)) implements Iterator#(
    .t : OwnedHashMapBorrow#(.key: key, .value: value)
)
OwnedHashMap#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(.key: key)) implements Iterable#(
    .t : OwnedHashMapBorrow#(.key: key, .value: value)
)

to_iterator#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .value : &OwnedHashMap#(.key: key, .value: value, .policy: policy)
    ) -> (
        .iterator : OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)
    ) := {
    generation ::= erase_reference#(.t: _OwnedHashShape)(.base = &value&._shape).reference
    owner ::= depend_on#(.t: &OwnedHashMap#(.key: key, .value: value, .policy: policy))(
        .value = value
        .on    = generation
    ).result
    iterator = (._owner = owner, ._generation = generation, ._index = 0)
}

_owned_hash_next#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self  : &OwnedHashMap#(.key: key, .value: value, .policy: policy),
        .start : UIntNative
    ) -> (
        .index : UIntNative
    ) := {
    index = start

    while index < capacity(self).count {
        if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state == 1 {
            return
        }
        index = index + 1
    }
}

has_next#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .ok : Bool
    ) := {
    ok = [
        _owned_hash_next(self&._owner, .start = self&._index).index
        < capacity(self&._owner).count
    ]
}

next#(
        .key    : Type,
        .value  : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : $&OwnedHashMapIterator#(.key: key, .value: value, .policy: policy)
    ) -> (
        .value : OwnedHashMapBorrow#(.key: key, .value: value)
    ) := {
    index ::= _owned_hash_next(self&._owner, .start = self&._index).index

    if index >= capacity(self&._owner).count { abort }
    entry ::= _owned_hash_entry(self&._owner, .index = index).entry
    borrowed_key ::= depend_on#(.t: &key)(.value = &entry&.key, .on = self&._generation).result
    borrowed_value ::= depend_on#(.t: &value)(.value = &entry&.value, .on = self&._generation).result
    value = (.key = borrowed_key, .value = borrowed_value)
    self&._index = index + 1
}

OwnedHashSetIterator#(.key: Type, .policy: Type: BorrowedHashPolicy#(.key: key)): Type = (
    ._entries : OwnedHashMapIterator#(.key: key, .value: _HashSetValue, .policy: policy)
)

OwnedHashSetIterator#(.key: Type, .policy: Type: BorrowedHashPolicy#(.key: key)) implements Iterator#(
    .t : &key
)
OwnedHashSet#(.key: Type, .policy: Type: BorrowedHashPolicy#(.key: key)) implements ROPointerIterable#(
    .t : key
)

to_ro_pointer_iterator#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .value : &OwnedHashSet#(.key: key, .policy: policy)
    ) -> (
        .iterator : OwnedHashSetIterator#(.key: key, .policy: policy)
    ) := { iterator = (._entries = to_iterator(.value = &value&._map).iterator) }

has_next#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : &OwnedHashSetIterator#(.key: key, .policy: policy)
    ) -> (
        .ok : Bool
    ) := { ok = has_next(&self&._entries).ok }

next#(
        .key    : Type,
        .policy : Type: BorrowedHashPolicy#(.key: key)
    )(
        .self : $&OwnedHashSetIterator#(.key: key, .policy: policy)
    ) -> (
        .value : &key
    ) := { value = next($&self&._entries).value.key }
