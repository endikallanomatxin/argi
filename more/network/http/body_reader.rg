-- Binds body framing state to one source. The source must remain dedicated to
-- this message until the body is finished or the connection is discarded.
BodyReader := #(.t: Type: BlockReader#(t)) (
    ._reader  : $&t
    ._state   : _BodyState
    ._failure : ?HttpReasons
)

BodyReaderInitArgs: Type = #(.t: Type: BlockReader#(t)) (
    .reader : $&t
    .head   : &RequestHead
    .limits : Limits       = Limits()
)

implement#(.t: Type: BlockReader#(t)) Init#(BodyReader#(t), BodyReaderInitArgs#(t)) (
    .Result : Type = BodyReader#(t)
    .init   = BodyReaderInitArgs#(t) -> (.result: Result) {
        result = (
            ._reader  = reader
            ._state   = _body_state(.head = head, .limits = limits).state
            ._failure = ..none
        )
    }
)

read_body := #(.t: Type: BlockReader#(t)) (
    .self: $&BodyReader#(t), .buffer: MutableArrayView#(UInt8)
) -> (.result: Errable#(UIntNative, HttpReasons)) {
    match _read_body_state#(.R: t)(
        .reader = self&._reader, .state = $&self&._state, .buffer = buffer
    ) {
        ..ok count { result = ..ok count }
        ..error error {
            if is(.value = self&._failure, .variant = ..none) {
                self&._failure = ..some(.value = error.reason)
            }
            result = ..error error
        }
    }
}

body_finished := #(.t: Type: BlockReader#(t)) (.self: &BodyReader#(t)) -> (.ok: Bool) {
    ok = _body_state_finished(.self = &self&._state).ok
}

body_failure := #(.t: Type: BlockReader#(t)) (.self: &BodyReader#(t)) -> (.reason: ?HttpReasons) {
    reason = self&._failure
}

_read_http_block := #(.t: Type: BlockReader#(t)) (
    .self: $&BodyReader#(t), .buffer: MutableArrayView#(UInt8)
) -> (.result: Errable#(UIntNative, (..stream_read_failed))) {
    match read_body(.self = self, .buffer = buffer) {
        ..ok count { result = ..ok count }
        ..error _ { result = ..error(.reason = ..stream_read_failed) }
    }
}

implement#(.t: Type: BlockReader#(t)) BlockReader#(BodyReader#(t)) (
    .read_block = _read_http_block
)
