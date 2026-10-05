OwnedByteLine: Type = (.bytes: DynamicArray#(.t: UInt8), .terminated: Bool)

-- Each returned line owns independent storage. LF terminates; a CR preceding
-- LF is removed. The raw payload limit includes CR. An exact fit may consume
-- one lookahead byte; callers must stop after any error. Capacity is reserved
-- before reading each payload byte, so allocation failure does not consume it.
read_line_owned(
        .self      : $&Reader,
        .maximum   : UIntNative,
        .allocator : $&Allocator = reach allocator
    ) -> (
        .result : Errable#(?OwnedByteLine, (..stream_read_failed, ..line_too_long, ..out_of_memory))
    ) := {
    assume allocator
    bytes ::= DynamicArray#(.t: UInt8)(.capacity = 1)!
    terminated ::= false

    while true {
        count ::= length(&bytes).count
        if count < maximum {
            ensure_capacity(.self = $&bytes, .capacity = count + 1)!
        }
        match read_byte(.self = self)! {
            ..end {
                if count == 0 {
                    result = ..ok ..none
                    return
                }
                break
            }
            ..ok byte {
                if byte == 10 {
                    terminated = true
                    break
                }
                if count == maximum {
                    result = ..error(.reason = ..line_too_long)
                    return
                }
                push_assume_capacity(.self = $&bytes, .value = byte)
            }
        }
    }

    count ::= length(&bytes).count

    if terminated and count > 0 {
        if unwrap_or_abort(.value = get(.self = &bytes, .index = count - 1)) == 13 {
            discarded ::= pop(.self = $&bytes)
        }
    }

    result = ..ok ..some(.value = (.bytes = ~bytes, .terminated = terminated))
}

-- Fallible iteration exposes EOF explicitly rather than hiding errors in a
-- has_next probe. Stop after an error; the failed reader cannot be resumed.
OwnedLineReader#(.t: Type: Reader): Type = (._source: $&t, ._maximum: UIntNative, ._ended: Bool)

OwnedLineReader init#(
        .t : Type: Reader
    )(
        .source  : $&t,
        .maximum : UIntNative
    ) -> (
        .result : OwnedLineReader#(.t: t)
    ) := { result = (._source = source, ._maximum = maximum, ._ended = false) }

next#(
        .t : Type: Reader
    )(
        .self      : $&OwnedLineReader#(.t: t),
        .allocator : $&Allocator                = reach allocator
    ) -> (
        .result : Errable#(?OwnedByteLine, (..stream_read_failed, ..line_too_long, ..out_of_memory))
    ) := {
    assume allocator

    if self&._ended {
        result = ..ok ..none
        return
    }

    self&._ended = true
    line ::= ~read_line_owned(
        .self    = self&._source
        .maximum = self&._maximum
    )!

    match line {
        ..none { result = ..ok ..none } ..some ~entry {
            self&._ended = false
            result = ..ok ..some(.value = ~entry.value)
        }
    }
}
