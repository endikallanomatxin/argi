-- A provider may complete the request and still return a submission error.
RejectingExecutor := (.ffi: $&ForeignFunctionInterface, .start: Bool)
implement Executor#(RejectingExecutor) (
    .state = region(self)
    .submit = (.self: $&RejectingExecutor, .request: TaskRequest) -> (
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

check_rejected_text := (.storage: $&GeneralPurposeAllocator, .ffi: $&ForeignFunctionInterface, .start: Bool) -> () {
    allocator ::= Virtual#(Allocator)(storage)
    provider ::= RejectingExecutor(ffi, start)
    assume executor ::= Virtual#(Executor)($&provider)
    match async#(make_text)(.args = (.allocator = allocator)) {
        ..ok ~future { abort }
        ..error failure { match failure.reason {
            ..task_start_failed {}
            ..unsupported_task_value { abort }
            ..executor_mismatch { abort }
        } }
    }
    if has_live_allocations(storage) { abort }
}
