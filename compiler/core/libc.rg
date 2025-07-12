-- Printing
putchar ( .character : Char ) -> () : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction

-- Allocation
malloc ( .size : Int32 ) -> ( .pointer: &Any) : ExternFunction
free ( .pointer: &Any ) -> () : ExternFunction
