Latch := (.open: Bool)

Retryable := (.open: Bool, .busy: Bool)

implement OpenState#(Latch) (
    .check_open = (.self: &Latch) -> (.ok: Bool) { ok = self&.open }
)

implement OpenState#(Retryable) (
    .check_open = (.self: &Retryable) -> (.ok: Bool) { ok = self&.open }
)

implement Closeable#(Latch) (
    .Result         : Type = Void
    .close_resource = (.self: $&Latch) -> (.result: Void) {
        self&.open = false
        result = Void()
    }
)

implement Closeable#(Retryable) (
    .Result         : Type = Errable#(Void, (..busy))
    .close_resource = (.self: $&Retryable) -> (.result: Result) {

        if self&.busy {
            result = ..error(.reason = ..busy)
            return
        }
        self&.open = false
        result = ..ok Void()
    }
)

finish := #(.Resource: Type: Closeable#(Resource)) (.self: $&Resource) -> (
    .result : Closeable#(Resource).Result
) {

    result = ~close(.self = self)
}

resource_open := #(.Resource: Type: OpenState#(Resource)) (.self: &Resource) -> (.ok: Bool) {
    ok = is_open(.self = self).ok
}

main := () -> (.status_code: Int32 = 0) {

    latch ::= Latch(.open = true)
    retryable ::= Retryable(.open = true, .busy = true)
    finish(.self = $&latch)
    if resource_open(.self = &latch).ok { status_code = 1 }

    match finish(.self = $&retryable) {
        ..ok _ { status_code = 2 }
        ..error item { if item.reason != ..busy { status_code = 3 } }
    }
    if resource_open(.self = &retryable).ok == false { status_code = 4 }
    retryable.busy = false
    unwrap_or_abort(.value = finish(.self = $&retryable))
    if resource_open(.self = &retryable).ok { status_code = 5 }
    unwrap_or_abort(.value = finish(.self = $&retryable))
}
