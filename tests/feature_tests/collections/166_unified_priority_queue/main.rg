run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    order ::= Int32OrderPolicy()
    queue ::= PriorityQueue#(.t: Int32)(.order = &order, .capacity = 1)!
    if is(.value = peek_reference(&queue).value, .variant = ..some) { abort }
    if is(.value = pop($&queue).result, .variant = ..some) { abort }
    index :: Int32 = 64
    while index > 0 {
        index = index - 1
        push($&queue, .value = index % 16)!
    }
    index = 0
    while index < 64 {
        expected ::= index / 4
        match peek_reference(&queue).value {
            ..none { abort }
            ..some item { if item.value&!= expected { abort } }
        }
        match peek(&queue).value {
            ..none { abort }
            ..some item { if item.value != expected { abort } }
        }
        match pop($&queue).result {
            ..none { abort }
            ..some item { if item.value != expected { abort } }
        }
        index = index + 1
    }
    if length(&queue).count != 0 { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
