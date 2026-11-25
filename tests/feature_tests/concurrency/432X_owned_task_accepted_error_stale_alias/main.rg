DiscardingExecutor := (.ffi: $&ForeignFunctionInterface, .start: Bool)
implement Executor#(DiscardingExecutor) (
    .state = region(self)
    .submit = (.self: $&DiscardingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        if self&.start {
            submitted ::= execute_inline(.request = ~pending, .ffi = self&.ffi)
            match submitted {
                ..ok ~receipt {}
                ..error _ { abort }
            }
        }
        result = ..error(.reason = ..task_start_failed)
    }
)

return_owner := (.value: Allocation) -> (.result: Allocation) { result = ~value }
main := (.system: System) -> () {
    provider ::= DiscardingExecutor(.ffi = system.ffi, .start = true)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    allocation ::= unwrap_or_abort(allocate_shared_c_storage(.self = shared, .size = 1, .alignment = 1, .zeroed = true))
    pointer ::= trusted_establish_allocation_slot#(.t: UInt8)(
        .allocation = &allocation, .slot = allocation.data, .anchor = allocation.anchor
    )
    match async_owned#(return_owner)(.args = (.value = ~allocation), .executor = executor, .ffi = system.ffi) {
        ..ok ~unexpected { abort }
        ..error _ {}
    }
    recover_ordinary(.owner = $&allocator)
    pointer& = 7
}
