main () -> (.status_code: Int32) := {
    text ::= String(.length = 3)

    bytes_set(.string = $&text, .index = 0, .value = 65)
    bytes_set(.string = $&text, .index = 1, .value = 114)
    bytes_set(.string = $&text, .index = 2, .value = 103)

    first ::= bytes_get(.string = &text, .index = 0).byte
    second ::= bytes_get(.string = &text, .index = 1).byte
    third ::= bytes_get(.string = &text, .index = 2).byte

    if first != 65 {
        status_code = 1
        return
    }

    if second != 114 {
        status_code = 2
        return
    }

    if third != 103 {
        status_code = 3
        return
    }

    status_code = 0
}
