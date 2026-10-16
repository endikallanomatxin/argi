-- StringView probes use the same digest and equality as owning String keys.
-- They never create a temporary owner or expose mutable keys.
_hash_string_find#(.value: Type)(
    .self: &HashMap#(.key: String, .value: value, .policy: StandardHashPolicy), .key: StringView
) -> (.index: ?UIntNative = ..none) := {
    digest ::= HashPolicy#(
        StandardHashPolicy, StringView
    ).hash(&self&._policy, .key = &key).hash
    count ::= capacity(self).count
    position ::= digest % count
    visited :: UIntNative = 0

    while visited < count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._table._slots, .index = position)
        if slot.state == 0 { return }
        if slot.state == 1 and slot.hash == digest {
            entry ::= _hash_entry(self, .index = position).entry
            if equals(.left = view(&entry&.key), .right = key).ok {
                index = ..some(.value = position)
                return
            }
        }
        position = position + 1
        if position == count { position = 0 }
        visited = visited + 1
    }
}

_map_contains_hash_string_lookup#(.value: Type) := (
    .self: &HashMap#(.key: String, .value: value, .policy: StandardHashPolicy), .key: StringView
) -> (.ok: Bool) {
    ok = _hash_string_find(self, .key = key).index ?
}

_map_get_reference_hash_string_lookup#(.value: Type) := (
    .self: &HashMap#(.key: String, .value: value, .policy: StandardHashPolicy), .key: StringView
) -> (.result: ?&value = ..none) {
    match _hash_string_find(self, .key = key).index {
        ..none {}
        ..some found {
            entry ::= _hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: &value)(
                .value = &entry&.value
                .on    = erase_reference#(.t: _HashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}

_map_get_mutable_reference_hash_string_lookup#(.value: Type)(
    .self : $&HashMap#(.key: String, .value: value, .policy: StandardHashPolicy),
    .key  : StringView
) -> (.result: ?$&value = ..none) := {
    match _hash_string_find(self, .key = key).index {
        ..none {}
        ..some found {
            entry ::= _hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: $&value)(
                .value = $&entry&.value
                .on    = erase_reference#(.t: _HashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}
