#if target_os("linux") or target_os("macos") {
    -- Native page acquisition/release boundary for the supported POSIX hosts.
    -- These constants describe the OS ABI, not the allocator or ownership model.
    _posix_memory_read_write: Int32 = 3
    _linux_private_anonymous: Int32 = 34
    _darwin_private_anonymous: Int32 = 4098

    _memory_getpagesize() -> (.size: UIntNative): ExternFunction
    _memory_mmap(
        .hint            : UIntNative,
        .length          : UIntNative,
        .protection      : Int32,
        .flags           : Int32,
        .file_descriptor : Int32,
        .offset          : UIntNative
    ) -> (.address: UIntNative): ExternFunction
    _memory_munmap(.address: UIntNative, .length: UIntNative) -> (.status: Int32): ExternFunction

    _memory_map_anonymous(.length: UIntNative) -> (.address: UIntNative) := {
        #if target_os("linux") {
            address = _memory_mmap(
                .hint            = 0,
                .length          = length,
                .protection      = _posix_memory_read_write,
                .flags           = _linux_private_anonymous,
                .file_descriptor = -1,
                .offset          = 0
            ).address
        }#else {
            address = _memory_mmap(
                .hint            = 0,
                .length          = length,
                .protection      = _posix_memory_read_write,
                .flags           = _darwin_private_anonymous,
                .file_descriptor = -1,
                .offset          = 0
            ).address
        }
    }

    -- POSIX may release alignment padding independently from the returned range.
    _memory_acquire_aligned(.length: UIntNative, .alignment: UIntNative) -> (.address: UIntNative) := {
        page_size ::= _memory_getpagesize().size
        extra :: UIntNative = 0
        if alignment > page_size { extra = alignment - page_size }
        request_size ::= length + extra
        if request_size < length {
            address = 0
            address = address - 1
            return
        }
        mapped_address ::= _memory_map_anonymous(.length = request_size).address
        if mapped_address + 1 == 0 {
            address = mapped_address
            return
        }
        if mapped_address + request_size < mapped_address { abort }
        address = mapped_address
        if alignment > page_size {
            remainder ::= mapped_address % alignment
            if remainder != 0 {
                padding ::= alignment - remainder
                address = mapped_address + padding
                if address < mapped_address { abort }
                if _memory_munmap(.address = mapped_address, .length = padding).status != 0 {
                    abort
                }
            }
            mapped_end ::= mapped_address + request_size
            used_end ::= address + length
            if used_end < mapped_end {
                if _memory_munmap(.address = used_end, .length = mapped_end - used_end).status != 0 {
                    abort
                }
            }
        }
        address = _trusted_acquisition_subaddress(.base = mapped_address, .address = address).result
    }

    _memory_release_aligned(.address: UIntNative, .length: UIntNative) -> (.status: Int32) := {
        status = _memory_munmap(.address = address, .length = length).status
    }

}
