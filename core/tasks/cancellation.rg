-- Cancellation is sticky and cooperative: requesting it does not interrupt
-- native blocking I/O or destroy task resources. The source owns one atomic
-- cell; observer tokens borrow it. Cross-thread transfer remains subject to
-- the language's transfer rules, independently of this native atomic storage.
CancellationSource: Type = (._state: AtomicUInt32)

CancellationSource init(
        .ffi : $&ForeignFunctionInterface = reach ffi
    ) -> (
        .result : Errable#(CancellationSource, (..out_of_memory))
    ) := {
    state ::= AtomicUInt32(.ffi = ffi)!

    result = ..ok(._state = ~state)
}

CancellationSource deinit(.self: $&CancellationSource) -> () := { deinit(.self = $&self&._state) }

CancellationToken: Type = (._source: &CancellationSource)

CancellationToken implements ImplicitlyCopyable

cancellation_token(.self: &CancellationSource) -> (.token: CancellationToken) := {
    token = (._source = self)
}

cancel(.self: $&CancellationSource) -> () := { store(.self = $&self&._state, .value = 1) }

is_cancelled(.self: CancellationToken) -> (.value: Bool) := {
    value = [
        load(.self = &self._source&._state).value
        != 0
    ]
}

CancellationContext: Type = (.token: ?CancellationToken = ..none, .deadline: ?Deadline = ..none)

CancellationContext implements ImplicitlyCopyable

-- The caller supplies a monotonic reading to make checkpoints deterministic
-- and avoid unnecessary system calls. Cancellation wins when both apply.
check_cancelled(
        .self : CancellationContext,
        .now  : MonotonicInstant
    ) -> (
        .result : Errable#(Void, (..cancelled, ..deadline_exceeded)) = ..ok Void()
    ) := {
    match self.token {
        ..none {}
        ..some entry {
            if is_cancelled(.self = entry.value).value {
                result = ..error(.reason = ..cancelled)
                return
            }
        }
    }

    match self.deadline {
        ..none {}
        ..some entry {
            if expired(.self = entry.value, .now = now).value {
                result = ..error(.reason = ..deadline_exceeded)
            }
        }
    }
}
