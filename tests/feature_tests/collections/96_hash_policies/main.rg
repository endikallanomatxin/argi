main := (.system: System) -> (.status_code: Int32 = 0) {
    policy ::= StandardHashPolicy()
    minimum: Int64 = -9223372036854775808
    same: Int64 = -9223372036854775808
    digest ::= HashPolicy#(StandardHashPolicy, Int64).hash(&policy, .key = &minimum).hash
    if digest != HashPolicy#(StandardHashPolicy, Int64).hash(&policy, .key = &same).hash {
        abort
    }
    if [
        HashPolicy#(StandardHashPolicy, Int64).equal(
            &policy, .left = &minimum, .right = &same
        ).ok
        == false
    ] { abort }
    maximum: UInt64 = 18446744073709551615
    _ ::= HashPolicy#(StandardHashPolicy, UInt64).hash(&policy, .key = &maximum)
    bytes: [3]UInt8 = (97, 0, 98)
    storage ::= unwrap_or_abort(
        .value = string_from_bytes(.bytes = view(&bytes), .allocator = system.page_allocator)
    )
    text ::= view(&storage)
    owned_hash ::= HashPolicy#(StandardHashPolicy, String).hash(
        &policy, .key = view(&storage)
    ).hash
    borrowed_hash ::= HashPolicy#(StandardHashPolicy, StringView).hash(&policy, .key = text).hash
    if owned_hash != borrowed_hash { abort }
    if HashPolicy#(StandardHashPolicy, StringView).equal(&policy, .left = text, .right = "ab").ok {
        abort
    }
    seeded: StandardHashPolicy = (.seed = 99)
    if [
        HashPolicy#(StandardHashPolicy, StringView).hash(&seeded, .key = text).hash
        == borrowed_hash
    ] { abort }
}
