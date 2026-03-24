-- Printing
putchar ( .character : UInt8 ) -> () : ExternFunction
getchar ( ) -> ( .character : Int32 ) : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction

-- Memory management
alloca ( .size : UIntNative ) -> ( .pointer: $&Any ) : ExternFunction
malloc ( .size : UIntNative ) -> ( .pointer: $&Any ) : ExternFunction
free ( .pointer: &Any ) -> () : ExternFunction
memcpy ( .dst  : $&Any, .src : &Any, .n : UIntNative ) -> () : ExternFunction
