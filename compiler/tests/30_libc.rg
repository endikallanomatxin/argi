putchar ( .c : Char ) -> () : ExternFunction

main () -> (.status_code: Int32) := {
    a := 'a'
    putchar(.c = a)
}
