main() -> (.status_code: Int32 = 0) := {
    text :: [8]UInt8 = (10, 97, 13, 10, 98, 99, 10, 100)
    reader ::= ByteReader(.bytes = view(.array = &text))
    storage :: [2]UInt8 = (0, 0)
    buffer ::= view(.array = $&storage)
    match unwrap_or_abort(.value = read_line(.self = $&reader, .buffer = buffer)) {
        ..none { abort }
        ..some line {
            if [
                length(.self = &line.value.bytes).count != 0
                or line.value.terminated == false
            ] { abort }
        }
    }
    match unwrap_or_abort(.value = read_line(.self = $&reader, .buffer = buffer)) {
        ..none { abort }
        ..some line {
            if [
                length(.self = &line.value.bytes).count != 1
                or line.value.terminated == false
            ] { abort }
        }
    }
    match unwrap_or_abort(.value = read_line(.self = $&reader, .buffer = buffer)) {
        ..none { abort }
        ..some line {
            if [
                length(.self = &line.value.bytes).count != 2
                or line.value.terminated == false
            ] { abort }
        }
    }
    match unwrap_or_abort(.value = read_line(.self = $&reader, .buffer = buffer)) {
        ..none { abort }
        ..some line {
            if length(.self = &line.value.bytes).count != 1 or line.value.terminated { abort }
        }
    }
    match unwrap_or_abort(.value = read_line(.self = $&reader, .buffer = buffer)) {
        ..none {} ..some _ { abort }
    }
    oversized :: [3]UInt8 = (1, 2, 3)
    long ::= ByteReader(.bytes = view(.array = &oversized))
    match read_line(.self = $&long, .buffer = buffer) { ..ok _ { abort } ..error _ {} }
    if position(.self = &long).count != 3 { abort }
}
