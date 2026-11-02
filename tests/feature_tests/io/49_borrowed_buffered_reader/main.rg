Source := (.position: UIntNative = 0, .calls: UIntNative = 0, .fail_once: Bool = false)

implement Reader#(Source) (
    .read_byte = (.self: $&Source) -> (.result: Errable#(ReadByte, (..stream_read_failed))) {

        self&.calls = self&.calls + 1
        if self&.fail_once and self&.position == 1 {
            self&.fail_once = false
            result = ..error(.reason = ..stream_read_failed)
            return
        }
        if self&.position == 3 {
            result = ..ok ..end
            return
        }
        self&.position = self&.position + 1
        byte :: UInt8 = 65
        if self&.position == 2 { byte = 66 }
        if self&.position == 3 { byte = 67 }
        result = ..ok ..ok byte
    }
)

expect_byte := #(.Stream: Type: Reader#(Stream)) (.reader: $&Stream, .expected: UInt8 = 65) -> (
) {

    match unwrap_or_abort(.value = Reader#().read_byte(reader)) {
        ..end { abort }
        ..ok byte { if byte != expected { abort } }
    }
}

main := () -> () {

    -- Empty storage is a deliberate unbuffered adapter, without lookahead.
    source :: Source = (.position = 0, .fail_once = false)
    empty: [0]UInt8 = ()
    direct ::= BufferedReader(.base = $&source, .buffer = view($&empty))
    expect_byte(.reader = $&direct)
    if source.calls != 1 or source.position != 1 { abort }
    expect_byte(.reader = $&direct, .expected = 66)
    expect_byte(.reader = $&direct, .expected = 67)
    match unwrap_or_abort(.value = Reader#().read_byte($&direct)) {
        ..end {}
        ..ok _ { abort }
    }
    if source.calls != 4 { abort }

    -- A failed refill must not publish its partially written prefix.
    failing :: Source = (.position = 0, .calls = 0, .fail_once = true)
    storage: [2]UInt8 = (99, 99)
    {
        buffered ::= BufferedReader(.base = $&failing, .buffer = view($&storage))
        match Reader#().read_byte($&buffered) {
            ..ok _ { abort }
            ..error error { match error.reason { ..stream_read_failed {} } }
        }
        if failing.position != 1 or failing.calls != 2 { abort }
        expect_byte(.reader = $&buffered, .expected = 66)
        if failing.position != 3 or failing.calls != 4 { abort }
        expect_byte(.reader = $&buffered, .expected = 67)
        if failing.calls != 4 { abort }
        match unwrap_or_abort(.value = Reader#().read_byte($&buffered)) {
            ..end {}
            ..ok _ { abort }
        }
    }
    -- Dropping the adapter neither destroys its base nor releases its buffer.
    storage[0] = 90
    failing.position = 0
    expect_byte(.reader = $&failing)
    if storage[0] != 90 { abort }
}
