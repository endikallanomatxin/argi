-- StringView probes use the same digest and equality as owning String keys.
-- They never create a temporary owner or expose mutable keys.
_owned_string_find#(
        .value : Type
    )(
        .self : &OwnedHashMap#(.key: String, .value: value, .policy: StringHashPolicy),
        .key  : StringView
    ) -> (
        .index : ?UIntNative = ..none
    ) := {
    digest ::= string_hash_map_hash(.key = &key).hash
    count ::= capacity(self).count
    position ::= digest % count
    visited :: UIntNative = 0

    while visited < count {
        slot ::= _trusted_dynamic_array_get(.array = &self&._table._slots, .index = position)
        if slot.state == 0 { return }
        if slot.state == 1 and slot.hash == digest {
            entry ::= _owned_hash_entry(self, .index = position).entry
            if equals(.left = as_view(&entry&.key), .right = key).ok {
                index = ..some(.value = position)
                return
            }
        }
        position = position + 1
        if position == count { position = 0 }
        visited = visited + 1
    }
}

contains#(
        .value : Type
    )(
        .self : &OwnedHashMap#(.key: String, .value: value, .policy: StringHashPolicy),
        .key  : StringView
    ) -> (
        .ok : Bool
    ) := {
    ok = _owned_string_find(self, .key = key).index ?
}

get_ro_ref#(
        .value : Type
    )(
        .self : &OwnedHashMap#(.key: String, .value: value, .policy: StringHashPolicy),
        .key  : StringView
    ) -> (
        .result : ?&value = ..none
    ) := {
    match _owned_string_find(self, .key = key).index {
        ..none {}
        ..some found {
            entry ::= _owned_hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: &value)(
                .value = &entry&.value
                .on    = erase_reference#(.t: _OwnedHashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}

get_ref#(
        .value : Type
    )(
        .self : $&OwnedHashMap#(.key: String, .value: value, .policy: StringHashPolicy),
        .key  : StringView
    ) -> (
        .result : ?$&value = ..none
    ) := {
    match _owned_string_find(self, .key = key).index {
        ..none {}
        ..some found {
            entry ::= _owned_hash_entry(self, .index = found.value).entry
            borrowed ::= depend_on#(.t: $&value)(
                .value = $&entry&.value
                .on    = erase_reference#(.t: _OwnedHashShape)(.base = &self&._shape).reference
            ).result
            result = ..some(.value = borrowed)
        }
    }
}
