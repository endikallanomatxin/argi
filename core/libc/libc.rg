-- Printing
putchar(.character: UInt8) -> (): ExternFunction

getchar() -> (.character: Int32): ExternFunction

puts(.string: &Char) -> (): ExternFunction

strlen(.string: &Char) -> (.length: UIntNative): ExternFunction

getenv(.name: &Char) -> (.value: &Char): ExternFunction

fdopen(.fd: Int32, .mode: &Char) -> (.stream: &Any): ExternFunction

fopen(.path: &Char, .mode: &Char) -> (.stream: &Any): ExternFunction

fclose(.stream: &Any) -> (.status: Int32): ExternFunction

fflush(.stream: &Any) -> (.status: Int32): ExternFunction

fread(
        .buffer : $&UInt8,
        .size   : UIntNative,
        .count  : UIntNative,
        .stream : &Any
    ) -> (
        .count : UIntNative
    ): ExternFunction

fwrite(
        .buffer : &UInt8,
        .size   : UIntNative,
        .count  : UIntNative,
        .stream : &Any
    ) -> (
        .count : UIntNative
    ): ExternFunction

feof(.stream: &Any) -> (.status: Int32): ExternFunction

ferror(.stream: &Any) -> (.status: Int32): ExternFunction

remove(.path: &Char) -> (.status: Int32): ExternFunction

rename(.old_path: &Char, .new_path: &Char) -> (.status: Int32): ExternFunction

access(.path: &Char, .mode: Int32) -> (.status: Int32): ExternFunction

-- Memory management
alloca(.size: UIntNative) -> (.pointer: $&Any): ExternFunction

_malloc(.size: UIntNative) -> (.address: UIntNative): ExternFunction

_aligned_alloc(.alignment: UIntNative, .size: UIntNative) -> (.address: UIntNative): ExternFunction

_free(.address: UIntNative) -> (): ExternFunction

_aligned_free(.address: UIntNative) -> (): ExternFunction

memcpy(.dst: $&Any, .src: &Any, .n: UIntNative) -> (): ExternFunction

fread_into(
        .buffer : ArrayView#(.t: UInt8),
        .stream : &Any,
    ) -> (
        .count : UIntNative
    ) := {
    if length(&buffer).count == 0 {
        count = 0
        return
    }

    count = fread(
        .buffer = data(&buffer).pointer
        .size   = 1
        .count  = length(&buffer).count
        .stream = stream
    ).count
}

_FileWriteBuffer#(.Buffer: Type): Contract = (
    .bytes: (.self: &Buffer) -> (.pointer: &UInt8)
)

_write_buffer_mutable(.self: &ArrayView#(.t: UInt8)) -> (.pointer: &UInt8) := {
    pointer = read_reference#(.t: UInt8)(.base = data(.self = self).pointer).reference
}

_write_buffer_readonly(.self: &ArrayViewRO#(.t: UInt8)) -> (.pointer: &UInt8) := {
    pointer = data(.self = self).pointer
}

implement _FileWriteBuffer#(ArrayView#(.t: UInt8)) (
    .bytes = _write_buffer_mutable
)
implement _FileWriteBuffer#(ArrayViewRO#(.t: UInt8)) (
    .bytes = _write_buffer_readonly
)

fwrite_from#(.Buffer: Type: _FileWriteBuffer#(Buffer)) := (
    .buffer: Buffer, .stream: &Any
) -> (.count: UIntNative) {
    if length(&buffer).count == 0 {
        count = 0
        return
    }
    count = fwrite(
        .buffer = _FileWriteBuffer#(Buffer).bytes(.self = &buffer).pointer
        .size = 1
        .count = length(&buffer).count
        .stream = stream
    ).count
}

-- Direct libc allocation requires its own foreign-call capability.
malloc(.size: UIntNative, .ffi: $&ForeignFunctionInterface) -> (.address: UIntNative) := {
    address = _malloc(.size = size).address
}

aligned_alloc(
        .alignment : UIntNative,
        .size      : UIntNative,
        .ffi       : $&ForeignFunctionInterface
    ) -> (
        .address : UIntNative
    ) := {
    address = _aligned_alloc(.alignment = alignment, .size = size).address
}

free(.address: UIntNative, .ffi: $&ForeignFunctionInterface) -> () := {
    _free(.address = address)
}

-- Aligned CRT storage has its own release operation on Windows.
aligned_free(.address: UIntNative, .ffi: $&ForeignFunctionInterface) -> () := {
    _aligned_free(.address = address)
}
