borrow#(.Source: Type: ViewOf#(Source)) := (.array: Source) -> (.result: ViewOf#(Source).Result) {
    result = view(.array = array)
}

main := () -> (.status_code: Int32 = 0) {
    values :: [3]Int32 = (1, 2, 3)
    mutable ::= borrow(.array = $&values)
    pointer ::= unwrap_or_abort(.value = get_mutable_reference(.self = $&mutable, .index = 1))
    pointer&= 42
    readonly ::= borrow(.array = &values)
    if unwrap_or_abort(.value = get_reference(.self = &readonly, .index = 1))&!= 42 {
        status_code = 1
    }
    empty :: [0]Int32 = ()
    empty_view ::= view(.array = &empty)
    if length(&empty_view) != 0 { status_code = 2 }
}
