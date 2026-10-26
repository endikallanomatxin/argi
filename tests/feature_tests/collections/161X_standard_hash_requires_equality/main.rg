Key := (.id: Int32)

implement ImplicitlyCopyable<Key> ()

implement<.State: Type: Hasher<State>> Hashable<Key, State> (
    .hash_into = (.key: &Key, .hasher: $&State) -> () {
        byte: UInt8 = 0
        Hasher<State>.write_bytes(hasher, .bytes = single_array_view(.data = &byte))
    }
)

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap<.key: Key, .value: Int32>())
}
