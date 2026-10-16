-- Equal keys must have equal hashes. Both operations must remain stable while
-- keys are stored; borrowed key bytes must remain live and unchanged.
HashPolicy#(.Policy: Type, .key: Type): Contract = (
    .hash : (.self: &Policy, .key: &key) -> (.hash: UIntNative)
    .eql  : (.self: &Policy, .left: &key, .right: &key) -> (.ok: Bool)
)

-- The standard policy combines Hashable evidence with borrowed equality.
StandardHashPolicy: Type = (.seed: UInt64 = 14695981039346656037)

implement ImplicitlyCopyable#(StandardHashPolicy) ()

_StandardHashKey#(.Key: Type): Contract = (
    Hashable#(Key, StandardHasher)
    Equal#(Key, Key, (.left: &Key, .right: &Key))
)

implement#(.Key: Type: Hashable#(Key, StandardHasher)) _StandardHashKey#(Key) ()

implement#(.Key: Type: _StandardHashKey#(Key)) HashPolicy#(StandardHashPolicy, Key) (
    .hash = (.self: &StandardHashPolicy, .key: &Key) -> (.hash: UIntNative) {
        hasher ::= StandardHasher(.seed = self&.seed)
        Hashable#(Key, StandardHasher).hash_into(.key = key, .hasher = $&hasher)
        hash = Hasher#(StandardHasher).finish(&hasher)
    }
    .eql = (.self: &StandardHashPolicy, .left: &Key, .right: &Key) -> (.ok: Bool) {
        ok = Equal#(
            Key, Key, (.left: &Key, .right: &Key)
        ).equal(.args = (.left = left, .right = right))
    }
)
