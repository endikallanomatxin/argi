-- Printing
putchar ( .character : UInt8 ) -> () : ExternFunction
getchar ( ) -> ( .character : Int32 ) : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction
strlen ( .string : &Char ) -> ( .length : UIntNative ) : ExternFunction
getenv ( .name : &Char ) -> ( .value : &Char ) #returns_fresh(value) : ExternFunction
fdopen ( .fd : Int32, .mode : &Char ) -> ( .stream : &Any ) #returns_fresh(stream) : ExternFunction
fopen ( .path : &Char, .mode : &Char ) -> ( .stream : &Any ) #returns_fresh(stream) : ExternFunction
fclose ( .stream : &Any ) -> ( .status : Int32 ) : ExternFunction
fflush ( .stream : &Any ) -> ( .status : Int32 ) : ExternFunction
fread ( .buffer : $&UInt8, .size : UIntNative, .count : UIntNative, .stream : &Any ) -> ( .count : UIntNative ) : ExternFunction
fwrite ( .buffer : &UInt8, .size : UIntNative, .count : UIntNative, .stream : &Any ) -> ( .count : UIntNative ) : ExternFunction
feof ( .stream : &Any ) -> ( .status : Int32 ) : ExternFunction
ferror ( .stream : &Any ) -> ( .status : Int32 ) : ExternFunction
remove ( .path : &Char ) -> ( .status : Int32 ) : ExternFunction
rename ( .old_path : &Char, .new_path : &Char ) -> ( .status : Int32 ) : ExternFunction
access ( .path : &Char, .mode : Int32 ) -> ( .status : Int32 ) : ExternFunction

-- Memory management
alloca ( .size : UIntNative ) -> ( .pointer: $&Any ) #returns_fresh(pointer) #raw_boundary : ExternFunction
malloc ( .size : UIntNative ) -> ( .pointer: $&Any ) #returns_fresh(pointer) #raw_boundary : ExternFunction
aligned_alloc ( .alignment : UIntNative, .size : UIntNative ) -> ( .pointer: $&Any ) #returns_fresh(pointer) #raw_boundary : ExternFunction
getpagesize ( ) -> ( .size : UIntNative ) : ExternFunction
free ( .pointer: &Any ) -> () #invalidates(pointer) #raw_boundary : ExternFunction
memcpy ( .dst  : $&Any, .src : &Any, .n : UIntNative ) -> () : ExternFunction

fread_into(
    .buffer: ArrayView#(.t: UInt8),
    .stream: &Any,
) -> (.count: UIntNative) := {
    count = fread(
        .buffer = buffer.data,
        .size = 1,
        .count = buffer.length,
        .stream = stream,
    ).count
}

fwrite_from(
    .buffer: ArrayView#(.t: UInt8),
    .stream: &Any,
) -> (.count: UIntNative) := {
    count = fwrite(
        .buffer = &buffer.data&,
        .size = 1,
        .count = buffer.length,
        .stream = stream,
    ).count
}

memcpy_bytes(
    .dst: ArrayView#(.t: UInt8),
    .src: ArrayView#(.t: UInt8),
) -> () #trusted_temporal := {
    memcpy(
        .dst = cast#(.to: $&Any)(.value = cast#(.to: UIntNative)(.value = dst.data)),
        .src = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = src.data)),
        .n = dst.length,
    )
}
