implement#(
    .key: Type: FalliblyCopyable#(key),
    .value: Type: FalliblyCopyable#(value),
    .policy: Type: FalliblyCopyable#(policy)
) FalliblyCopyable#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .reasons: Type = choice_union#(
        .a: choice_union#(
            .a: FalliblyCopyable#(key).reasons,
            .b: FalliblyCopyable#(value).reasons
        ),
        .b: choice_union#(
            .a: FalliblyCopyable#(policy).reasons,
            .b: (..out_of_memory)
        )
    )

    .copy = (
        .self: &HashMap#(.key: key, .value: value, .policy: policy),
        .allocator: Virtual#(Allocator)
    ) -> (.result: Errable#(HashMap#(.key: key, .value: value, .policy: policy), reasons)) {
        copied_policy ::= FalliblyCopyable#(policy).copy(&self&._policy, .allocator = allocator)!
        out ::= _init_hash_map#(.key: key, .value: value)(
            .policy = ~copied_policy,
            .allocator = allocator,
            .capacity = capacity(self).count
        )!

        index :: UIntNative = 0
        while index < capacity(self).count {
            if _trusted_dynamic_array_get(.array = &self&._table._slots, .index = index).state == 1 {
                entry ::= _hash_entry(self, .index = index).entry
                copied_key ::= FalliblyCopyable#(key).copy(&entry&.key, .allocator = allocator)!
                copied_value ::= FalliblyCopyable#(value).copy(&entry&.value, .allocator = allocator)!
                -- Rehash copied keys under the copied policy. Lexical owners
                -- clean up both the occupied prefix and an unfinished entry.
                put($&out, .key = ~copied_key, .value = ~copied_value, .allocator = allocator)!
            }
            index = index + 1
        }

        result = ..ok ~out
    }
)
