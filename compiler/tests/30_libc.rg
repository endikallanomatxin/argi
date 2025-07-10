-- Printing
putchar ( .character : Char ) -> () : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction

-- Allocation
malloc ( .size : Int32 ) -> ( .pointer: &Any) : ExternFunction
free ( .pointer: &Any ) -> () : ExternFunction

main () -> (.status_code: Int32) := {
    puts(.string="Hello world!")

    p : &Char = malloc(.size=14)
    p& = '0'
    puts(.string=p)
    free(.pointer=p)

    putchar(.character='\n')
    status_code = 0
}

