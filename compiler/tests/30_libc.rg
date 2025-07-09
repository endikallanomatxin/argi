println ( .msg : &Char ) -> () : ExternFunction

main () -> (.status_code: Int32) := {
    a := 'a'
    println(.msg = &a)
}
