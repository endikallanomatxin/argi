make_array := () -> (.result: [2]Int32) { result = (20, 22) }

main := () -> (.status_code: Int32) {
    values :: [2](.data: $&[2]Int32 = $&make_array()) = (
        (),
        ()
    )
    values[0].data&[0] = 7
    if values[1].data&[0] != 20 { abort }
    status_code = values[1].data&[0] + values[1].data&[1]
}
