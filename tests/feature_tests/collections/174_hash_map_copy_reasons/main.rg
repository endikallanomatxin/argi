..key_copy_failed
..value_copy_failed
..policy_copy_failed

fail_kind :: Int32 = 0
key_drops :: Int32 = 0
value_drops :: Int32 = 0
policy_drops :: Int32 = 0

Key := (.number: Int32)
Value := (.number: Int32)
Policy := (.number: Int32)

implement Deinit#(Key) (
    .deinit = (.self: $&Key) -> () { key_drops = key_drops + 1 }
)
implement Deinit#(Value) (
    .deinit = (.self: $&Value) -> () { value_drops = value_drops + 1 }
)
implement Deinit#(Policy) (
    .deinit = (.self: $&Policy) -> () { policy_drops = policy_drops + 1 }
)
implement FalliblyCopyable#(Key) (
    .reasons: Type = (..key_copy_failed)
    .copy = (.self: &Key, .allocator: Virtual#(Allocator)) -> (.result: Errable#(Key, (..key_copy_failed))) {
        if fail_kind == 1 { result = ..error(.reason = ..key_copy_failed)
            return }
        result = ..ok(.number = self&.number)
    }
)
implement FalliblyCopyable#(Value) (
    .reasons: Type = (..value_copy_failed)
    .copy = (.self: &Value, .allocator: Virtual#(Allocator)) -> (.result: Errable#(Value, (..value_copy_failed))) {
        if fail_kind == 2 { result = ..error(.reason = ..value_copy_failed)
            return }
        result = ..ok(.number = self&.number)
    }
)
implement FalliblyCopyable#(Policy) (
    .reasons: Type = (..policy_copy_failed)
    .copy = (.self: &Policy, .allocator: Virtual#(Allocator)) -> (.result: Errable#(Policy, (..policy_copy_failed))) {
        if fail_kind == 3 { result = ..error(.reason = ..policy_copy_failed)
            return }
        result = ..ok(.number = self&.number)
    }
)
implement HashPolicy#(Policy, Key) (
    .Query: Type = Int32
    .query = (.self: &Policy, .key: &Key) -> (.query: Query) { query = key&.number }
    .hash = (.self: &Policy, .key: Int32) -> (.hash: UIntNative) { hash = 0 }
    .equal = (.self: &Policy, .left: Int32, .right: Int32) -> (.ok: Bool) { ok = left == right }
)

FailAllocator: Type = ()

implement Allocator#(FailAllocator) (
    .allocate = (.self: $&FailAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result: Errable#(Allocation, (..out_of_memory))
    ) {
        result = ..error(.reason = ..out_of_memory)
    }
)

require_reasons := #(
    .t: Type: FalliblyCopyable#(.Value: t, .reasons: (
        ..key_copy_failed, ..out_of_memory, ..policy_copy_failed, ..value_copy_failed
    ))
) (.value: &t) -> () {}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator := Virtual#(Allocator)($&allocator_storage)
    policy ::= Policy(1)
    source ::= unwrap_or_abort(HashMap#(.key: Key, .value: Value, .policy: Policy)(.policy = ~policy))
    key ::= Key(7)
    value ::= Value(9)
    unwrap_or_abort(put($&source, .key = ~key, .value = ~value))
    require_reasons(&source)

    failing ::= FailAllocator()
    failing_virtual ::= Virtual#(Allocator)($&failing)
    outcome_allocation ::= copy(.self = &source, .allocator = failing_virtual)
    match outcome_allocation {
        ..ok ~map { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if policy_drops != 1 or key_drops != 0 or value_drops != 0 { abort }

    fail_kind = 3
    outcome_policy ::= copy(.self = &source, .allocator = allocator)
    match outcome_policy {
        ..ok ~map { abort }
        ..error error { if error.reason != ..policy_copy_failed { abort } }
    }
    if policy_drops != 1 or key_drops != 0 or value_drops != 0 { abort }
    fail_kind = 1
    outcome_key ::= copy(.self = &source, .allocator = allocator)
    match outcome_key {
        ..ok ~map { abort }
        ..error error { if error.reason != ..key_copy_failed { abort } }
    }
    if policy_drops != 2 or key_drops != 0 or value_drops != 0 { abort }
    fail_kind = 2
    outcome_value ::= copy(.self = &source, .allocator = allocator)
    match outcome_value {
        ..ok ~map { abort }
        ..error error { if error.reason != ..value_copy_failed { abort } }
    }
    if policy_drops != 3 or key_drops != 1 or value_drops != 0 { abort }
    query :: Int32 = 7
    if contains(&source, .key = query).ok == false { abort }
    deinit($&source)
    if policy_drops != 4 or key_drops != 2 or value_drops != 1 { abort }
}
