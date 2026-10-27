..line_too_long

ByteLine := (.bytes: ArrayView#(.t: UInt8), .terminated: Bool)

-- LF terminates a line; remove a preceding CR only when LF was consumed.
-- A full buffer needs one byte of lookahead to distinguish an exact fit.
read_line := #(.SelfType: Type: Reader#(SelfType)) (
    .self: $&SelfType, .buffer: MutableArrayView#(.t: UInt8)
) -> (.result: Errable#(?ByteLine, (..stream_read_failed, ..line_too_long))) {
    read_result ::= read_until(self, .buffer = buffer, .delimiter = 10)!
    count ::= read_result.count
    terminated ::= false

    match read_result.termination {
        ..delimiter { terminated = true }
        ..end { if count == 0 {
                result = ..ok ..none
                return
            } }
        ..limit {
            match Reader#().read_byte(self)! {
                ..end { if count == 0 {
                        result = ..ok ..none
                        return
                    } }
                ..ok byte {
                    if byte != 10 {
                        result = ..error(.reason = ..line_too_long)
                        return
                    }
                    terminated = true
                }
            }
        }
    }

    if terminated and count > 0 {
        last ::= unwrap_or_abort(.value = get_reference(&buffer, .index = count - 1))
        if last&== 13 { count = count - 1 }
    }

    prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = count))

    result = ..ok ..some(
        .value = (.bytes = as_readonly(&prefix).view, .terminated = terminated)
    )
}
