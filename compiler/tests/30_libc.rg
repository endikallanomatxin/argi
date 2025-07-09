putchar ( .c : Char ) -> () : ExternFunction

main () -> (.status_code: Int32) := {
    putchar(.c='a')
    putchar(.c='b')
    putchar(.c='c')
}

