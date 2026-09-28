-- Printing
putchar ( .character : UInt8 ) -> () : ExternFunction
getchar ( ) -> ( .character : Int32 ) : ExternFunction
puts ( .string : &Char ) -> () : ExternFunction
strlen ( .string : &Char ) -> ( .length : UIntNative ) : ExternFunction
getenv ( .name : &Char ) -> ( .value : &Char ) : ExternFunction
fdopen ( .fd : Int32, .mode : &Char ) -> ( .stream : &Any ) : ExternFunction
fopen ( .path : &Char, .mode : &Char ) -> ( .stream : &Any ) : ExternFunction
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
alloca ( .size : UIntNative ) -> ( .pointer: $&Any ) : ExternFunction
malloc ( .size : UIntNative ) -> ( .address: UIntNative ) : ExternFunction
aligned_alloc ( .alignment : UIntNative, .size : UIntNative ) -> ( .address: UIntNative ) : ExternFunction
getpagesize ( ) -> ( .size : UIntNative ) : ExternFunction
-- POSIX virtual-memory mapping used by the page-backed allocators.
-- MAP_FAILED is the all-ones address.
mmap ( .hint: UIntNative, .length: UIntNative, .protection: Int32, .flags: Int32, .file_descriptor: Int32, .offset: UIntNative ) -> ( .address: UIntNative ) : ExternFunction
munmap ( .address: UIntNative, .length: UIntNative ) -> ( .status: Int32 ) : ExternFunction
free ( .address: UIntNative ) -> () : ExternFunction
memcpy ( .dst  : $&Any, .src : &Any, .n : UIntNative ) -> () : ExternFunction

fread_into(
    .buffer: ArrayView#(.t: UInt8),
    .stream: &Any,
) -> (.count: UIntNative) := {
    count = fread(
        .buffer = data#(.t: UInt8)(.self = &buffer).pointer,
        .size = 1,
        .count = length#(.t: UInt8)(.self = &buffer).count,
        .stream = stream,
    ).count
}

fwrite_from(
    .buffer: ArrayView#(.t: UInt8),
    .stream: &Any,
) -> (.count: UIntNative) := {
    count = fwrite(
        .buffer = read_reference#(.t: UInt8)(.base = data#(.t: UInt8)(.self = &buffer).pointer).reference,
        .size = 1,
        .count = length#(.t: UInt8)(.self = &buffer).count,
        .stream = stream,
    ).count
}

memcpy_bytes(
    .dst: ArrayView#(.t: UInt8),
    .src: ArrayView#(.t: UInt8),
) -> () := {
    if length#(.t: UInt8)(.self = &dst).count > length#(.t: UInt8)(.self = &src).count { abort }
    memcpy(
        .dst = mutable_reinterpret_reference#(.from: UInt8, .to: Any)(.base = data#(.t: UInt8)(.self = &dst).pointer).reference,
        .src = reinterpret_reference#(.from: UInt8, .to: Any)(.base = read_reference#(.t: UInt8)(.base = data#(.t: UInt8)(.self = &src).pointer).reference).reference,
        .n = length#(.t: UInt8)(.self = &dst).count,
    )
}

memcpy_bytes(
    .dst: ArrayView#(.t: UInt8),
    .src: ArrayViewRO#(.t: UInt8),
) -> () := {
    if length#(.t: UInt8)(.self = &dst).count > length#(.t: UInt8)(.self = &src).count { abort }
    memcpy(
        .dst = mutable_reinterpret_reference#(.from: UInt8, .to: Any)(.base = data#(.t: UInt8)(.self = &dst).pointer).reference,
        .src = reinterpret_reference#(.from: UInt8, .to: Any)(.base = data#(.t: UInt8)(.self = &src).pointer).reference,
        .n = length#(.t: UInt8)(.self = &dst).count,
    )
}
