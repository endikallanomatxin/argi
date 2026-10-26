Key := (.id: Int32)

implement<.State: Type: Hasher<State>> Hashable<Key, State> (
    .hash_into = (.key: &Key, .hasher: $&State) -> () {
        Hashable<Int32, State>.hash_into(.key = &key&.id, .hasher = hasher)
    }
)

Counter := (.bytes: UIntNative = 0)

implement Hasher<Counter> (
    .write_bytes = (.self: $&Counter, .bytes: ArrayView<UInt8>) -> () {
        self&.bytes = self&.bytes + length(&bytes)
    }
    .finish = (.self: &Counter) -> (.hash: UIntNative) { hash = self&.bytes }
)

main := () -> () {
    key: Key = (.id = 42)
    counter :: Counter = (.bytes = 0)
    Hashable<Key, Counter>.hash_into(.key = &key, .hasher = $&counter)
    if counter.bytes != 4 { abort }
    byte: UInt8 = 7
    Hashable<UInt8, Counter>.hash_into(.key = &byte, .hasher = $&counter)
    if counter.bytes != 5 { abort }
}
