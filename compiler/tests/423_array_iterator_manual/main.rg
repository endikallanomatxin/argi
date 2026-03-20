main () -> (.status_code: Int32) := {
    values : Array#(.n = 3, .t: Int32) = (2, 4, 6)
    it ::= to_iterator(.value = &values)
    sum :: Int32 = 0

    while has_next(.self = &it) {
        value :: Int32 = next(.self = $&it)
        sum = sum + value
    }

    if sum != 12 {
        status_code = 1
        return
    }

    status_code = 0
}
