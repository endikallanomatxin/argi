#if target_os("linux") or target_os("macos") {
    -- Native page acquisition/release boundary for the supported POSIX hosts.
    -- These constants describe the OS ABI, not the allocator or ownership model.
    _posix_memory_read_write: Int32 = 3
    _linux_private_anonymous: Int32 = 34
    _darwin_private_anonymous: Int32 = 4098

    _memory_getpagesize() -> (.size: UIntNative): ExternFunction where { no_access() }
    _memory_mmap(
        .hint            : UIntNative,
        .length          : UIntNative,
        .protection      : Int32,
        .flags           : Int32,
        .file_descriptor : Int32,
        .offset          : UIntNative
    ) -> (.address: UIntNative): ExternFunction
    -- Callers hold custody of the specified mapping or of the padding being
    -- trimmed. Unmapping changes that range's lifetime and accesses no other
    -- Argi storage.
    _memory_munmap(.address: UIntNative, .length: UIntNative) -> (.status: Int32): ExternFunction where {
        no_access()
        isolated()
    }

    _memory_map_anonymous := (.length: UIntNative, .ffi: $&ForeignFunctionInterface) -> (
        .address : UIntNative
    ) {
        assume ffi
        #if target_os("linux") {
            address = _memory_mmap(
                .hint            = 0
                .length          = length
                .protection      = _posix_memory_read_write
                .flags           = _linux_private_anonymous
                .file_descriptor = -1
                .offset          = 0
            ).address
        } #else {
            address = _memory_mmap(
                .hint            = 0
                .length          = length
                .protection      = _posix_memory_read_write
                .flags           = _darwin_private_anonymous
                .file_descriptor = -1
                .offset          = 0
            ).address
        }
    }

    -- This operation receives sizes only. Every unmap trims the fresh mapping
    -- made by this invocation. A result of one denotes failure and cannot be
    -- the base of a page-aligned mapping.
    _memory_acquire_aligned := (
        .length: UIntNative, .alignment: UIntNative, .ffi: $&ForeignFunctionInterface
    ) -> (.address: UIntNative) {
        assume ffi
        page_size ::= _memory_getpagesize().size
        _require_allocation_alignment(.alignment = alignment)
        if page_size == 0 or length == 0 or length % page_size != 0 {
            address = 1
            return
        }
        extra :: UIntNative = 0
        if alignment > page_size { extra = alignment - page_size }
        request_size ::= length + extra
        if request_size < length {
            address = 1
            return
        }
        mapped_address ::= _memory_map_anonymous(.length = request_size).address
        if mapped_address + 1 == 0 {
            address = 1
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
                if [
                    _memory_munmap(.address = used_end, .length = mapped_end - used_end).status
                    != 0
                ] {
                    abort
                }
            }
        }
    }

    _memory_acquire_storage := (
        .length: UIntNative, .alignment: UIntNative, .ffi: $&ForeignFunctionInterface
    ) -> (.result: Errable#(AcquiredStorage, (..out_of_memory))) {
        address ::= _memory_acquire_aligned(.length = length, .alignment = alignment, .ffi = ffi).address
        if address == 1 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        result = ..ok(._address = address, ._size = length, ._alignment = alignment)
    }

    _memory_release_aligned := (
        .address: UIntNative, .length: UIntNative, .ffi: $&ForeignFunctionInterface
    ) -> (.status: Int32) {
        status = _memory_munmap(.address = address, .length = length, .ffi = ffi).status
    }

}
