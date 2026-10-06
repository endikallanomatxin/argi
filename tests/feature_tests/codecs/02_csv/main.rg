csv ::= import ("codecs/serialization/csv")

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    reader ::= csv.CsvReader(.text = "first,\"a,b\",\"say \"\"hi\"\"\"\r\n\"two\nlines\",\n")
    first ::= ~csv.next(.self = $&reader, .allocator = allocator)!
    match first {
        ..none { abort } ..some ~entry {
            if length(.self = &entry.value.fields).count != 3 { abort }
            field ::= unwrap_or_abort(.value = get_ro_ref(.self = &entry.value.fields, .index = 2))
            if as_view(.self = field) != "say \"hi\"" { abort }
        }
    }
    second ::= ~csv.next(.self = $&reader, .allocator = allocator)!
    match second {
        ..none { abort } ..some ~entry {
            if length(.self = &entry.value.fields).count != 2 { abort }
            field ::= unwrap_or_abort(.value = get_ro_ref(.self = &entry.value.fields, .index = 0))
            if as_view(.self = field) != "two\nlines" { abort }
        }
    }
    match csv.next(.self = $&reader, .allocator = allocator)! { ..none {} ..some ~_ { abort } }
    bad ::= csv.CsvReader(.text = "\"unclosed")
    match csv.next(.self = $&bad, .allocator = allocator) {
        ..ok ~_ { abort } ..error error { if [
                error.reason
                != ..invalid_csv
            ] { abort } }
    }
    match csv.next(.self = $&bad, .allocator = allocator)! { ..none {} ..some ~_ { abort } }
    bounded ::= csv.CsvReader(.text = "large", .maximum_field_bytes = 2)
    match csv.next(.self = $&bounded, .allocator = allocator) {
        ..ok ~_ { abort } ..error error { if [
                error.reason
                != ..size_limit_exceeded
            ] { abort } }
    }
    fields :: [2]StringView = ("a,b", "\"quoted\"")
    storage ::= zeroed#(.t: [64]UInt8)()
    writer ::= ByteWriter(.bytes = view(.array = $&storage))
    csv.write_record(.writer = $&writer, .fields = view(.array = &fields))!
    text :: StringView = (.data = &storage[0], .length = 20)
    if text != "\"a,b\",\"\"\"quoted\"\"\"\r\n" { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
