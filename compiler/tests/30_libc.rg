-- Printing
putchar ( .c : Char ) -> () : ExternFunction
puts ( .s : &Char ) -> () : ExternFunction

-- Allocation
malloc ( .size : Int32 ) -> ( .pointer: &Char) : ExternFunction
free ( .pointer: &Char ) -> () : ExternFunction

main () -> (.status_code: Int32) := {
    putchar(.c='h')
    putchar(.c='e')
    putchar(.c='l')
    putchar(.c='l')
    putchar(.c='o')
    putchar(.c=' ')
    putchar(.c='w')
    putchar(.c='o')
    putchar(.c='r')
    putchar(.c='l')
    putchar(.c='d')
    putchar(.c='!')
    putchar(.c='\n')

    puts(.s="Hello, world!")

    p :&Char = malloc(.size=14)
    puts(.s=p)
    free(.pointer=p)

    status_code = 0
}

