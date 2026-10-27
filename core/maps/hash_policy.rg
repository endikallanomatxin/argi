-- Stored keys and lookup inputs use one canonical query representation.
-- Equivalent queries must have equal hashes, stable while keys are stored.
HashPolicy#(.Policy: Type, .key: Type): Contract = (
    .Query : Type
    ImplicitlyCopyable#(Query)
    .query : (.self: &Policy, .key: &key) -> (.query: Query)
    .hash  : (.self: &Policy, .key: Query) -> (.hash: UIntNative)
    .equal : (.self: &Policy, .left: Query, .right: Query) -> (.ok: Bool)
)

-- The standard policy combines Hashable evidence with borrowed equality.
StandardHashPolicy := (.seed: UInt64 = 14695981039346656037)

implement ImplicitlyCopyable#(StandardHashPolicy) ()

_StandardHashKey#(.Key: Type): Contract = (
    Hashable#(Key, StandardHasher)
    Equal#(Key, Key, (.left: &Key, .right: &Key))
)

implement#(.Key: Type: Hashable#(Key, StandardHasher)) _StandardHashKey#(Key) ()

implement#(.Key: Type: _StandardHashKey#(Key)) HashPolicy#(StandardHashPolicy, Key) (
    .Query : Type = &Key
    .query = (.self: &StandardHashPolicy, .key: &Key) -> (.query: Query) { query = key }
    .hash  = (.self: &StandardHashPolicy, .key: &Key) -> (.hash: UIntNative) {
        hasher ::= StandardHasher(.seed = self&.seed)
        Hashable#(Key, StandardHasher).hash_into(.key = key, .hasher = $&hasher)
        hash = Hasher#(StandardHasher).finish(&hasher)
    }
    .equal = (.self: &StandardHashPolicy, .left: &Key, .right: &Key) -> (.ok: Bool) {
        ok = Equal#(
            Key, Key, (.left: &Key, .right: &Key)
        ).equal(.args = (.left = left, .right = right))
    }
)

implement HashPolicy#(StandardHashPolicy, String) (
    .Query : Type = StringView
    .query = (.self: &StandardHashPolicy, .key: &String) -> (.query: Query) {
        query = view(key)
    }
    .hash = (.self: &StandardHashPolicy, .key: StringView) -> (.hash: UIntNative) {
        hasher ::= StandardHasher(.seed = self&.seed)
        Hashable#(StringView, StandardHasher).hash_into(.key = &key, .hasher = $&hasher)
        hash = Hasher#(StandardHasher).finish(&hasher)
    }
    .equal = (.self: &StandardHashPolicy, .left: StringView, .right: StringView) -> (.ok: Bool) {
        ok = equals(.left = left, .right = right).ok
    }
)

implement HashPolicy#(StandardHashPolicy, StringView) (
    .Query : Type = StringView
    .query = (.self: &StandardHashPolicy, .key: &StringView) -> (.query: Query) { query = key&}
    .hash  = (.self: &StandardHashPolicy, .key: StringView) -> (.hash: UIntNative) {
        hasher ::= StandardHasher(.seed = self&.seed)
        Hashable#(StringView, StandardHasher).hash_into(.key = &key, .hasher = $&hasher)
        hash = Hasher#(StandardHasher).finish(&hasher)
    }
    .equal = (.self: &StandardHashPolicy, .left: StringView, .right: StringView) -> (.ok: Bool) {
        ok = equals(.left = left, .right = right).ok
    }
)
