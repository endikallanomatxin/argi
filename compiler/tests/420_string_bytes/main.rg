main () -> (.status_code: Int32) := {
    text ::= String(.length = 3)

    text[0] = 65
    text[1] = 114
    text[2] = 103

    first ::= text[0]
    second ::= text[1]
    third ::= text[2]

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
