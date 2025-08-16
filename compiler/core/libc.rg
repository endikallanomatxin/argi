-- Printing
putchar ( .character : Char ) -> () : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction

-- Memory management
alloca ( .size : Int32 ) -> ( .pointer: &Any ) : ExternFunction
malloc ( .size : Int32 ) -> ( .pointer: &Any ) : ExternFunction
free ( .pointer: &Any ) -> () : ExternFunction
memcpy ( .dst  : &Any, .src : &Any, .n : UInt64 ) -> () : ExternFunction

