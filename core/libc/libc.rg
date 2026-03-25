-- Printing
putchar ( .character : UInt8 ) -> () : ExternFunction
getchar ( ) -> ( .character : Int32 ) : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction
strlen ( .string : &Char ) -> ( .length : UIntNative ) : ExternFunction
fdopen ( .fd : Int32, .mode : &Char ) -> ( .stream : $&Any ) : ExternFunction
fopen ( .path : &Char, .mode : &Char ) -> ( .stream : $&Any ) : ExternFunction
fclose ( .stream : &Any ) -> ( .status : Int32 ) : ExternFunction
fflush ( .stream : &Any ) -> ( .status : Int32 ) : ExternFunction
fread ( .buffer : $&UInt8, .size : UIntNative, .count : UIntNative, .stream : &Any ) -> ( .count : UIntNative ) : ExternFunction
fwrite ( .buffer : &UInt8, .size : UIntNative, .count : UIntNative, .stream : &Any ) -> ( .count : UIntNative ) : ExternFunction

-- Memory management
alloca ( .size : UIntNative ) -> ( .pointer: $&Any ) : ExternFunction
malloc ( .size : UIntNative ) -> ( .pointer: $&Any ) : ExternFunction
free ( .pointer: &Any ) -> () : ExternFunction
memcpy ( .dst  : $&Any, .src : &Any, .n : UIntNative ) -> () : ExternFunction
