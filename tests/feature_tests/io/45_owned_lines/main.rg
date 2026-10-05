main(
        .system : System
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..stream_read_failed, ..line_too_long, ..out_of_memory)
        ) = ..ok Void()
    ) := {
    assume allocator := system.page_allocator
    data :: [7]UInt8 = (97, 13, 10, 10, 98, 99, 100)
    source ::= ByteReader(.bytes = view(.array = &data))
    lines ::= OwnedLineReader#(.t: ByteReader)(.source = $&source, .maximum = 3)
    first ::= ~next(.self = $&lines, .allocator = allocator)!
    match first {
        ..none { abort } ..some&entry {
            if [
                length(.self = &entry&.value.bytes).count != 1
                or entry&.value.terminated == false
            ] { abort }
        }
    }
    match next(.self = $&lines, .allocator = allocator)! {
        ..none { abort } ..some ~entry {
            if [
                length(.self = &entry.value.bytes).count
                != 0
            ] { abort }
        }
    }
    match next(.self = $&lines, .allocator = allocator)! {
        ..none { abort } ..some ~entry {
            if [
                length(.self = &entry.value.bytes).count != 3
                or entry.value.terminated
            ] { abort }
        }
    }
    match next(.self = $&lines, .allocator = allocator)! { ..none {} ..some ~_ { abort } }
    match first {
        ..none { abort } ..some&entry {
            if [
                unwrap_or_abort(.value = get(.self = &entry&.value.bytes, .index = 0))
                != 97
            ] { abort }
        }
    }
    other ::= ByteReader(.bytes = view(.array = &data))
    {
        limited ::= LimitedByteReader#(.t: ByteReader)(.source = $&other, .limit = 1)
        match read_byte(.self = $&limited)! {
            ..end { abort } ..ok byte { if byte != 97 { abort } }
        }
        match read_byte(.self = $&limited)! { ..end {} ..ok _ { abort } }
    }
    if position(.self = &other).count != 1 { abort }
    too_long ::= ByteReader(.bytes = view(.array = &data))
    match read_line_owned(.self = $&too_long, .maximum = 0, .allocator = allocator) {
        ..ok ~_ { abort } ..error&err { if [
                err&.reason
                != ..line_too_long
            ] { abort } }
    }
}
