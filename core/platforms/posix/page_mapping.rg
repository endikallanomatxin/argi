-- Native page acquisition/release boundary for the supported POSIX hosts.
-- These constants describe the OS ABI, not the allocator or ownership model.
_posix_memory_read_write : Int32 = 3
_linux_private_anonymous : Int32 = 34
_darwin_private_anonymous : Int32 = 4098

_memory_getpagesize() -> (.size: UIntNative) : ExternFunction
_memory_mmap(.hint: UIntNative, .length: UIntNative, .protection: Int32, .flags: Int32, .file_descriptor: Int32, .offset: UIntNative) -> (.address: UIntNative) : ExternFunction
_memory_munmap(.address: UIntNative, .length: UIntNative) -> (.status: Int32) : ExternFunction

_memory_map_anonymous(.length: UIntNative) -> (.address: UIntNative) := {
    -- Anonymous mapping flags differ between supported POSIX ABIs. Keep this
    -- compatibility policy inside the platform boundary; allocator code only
    -- requests a byte extent and handles MAP_FAILED.
    address = _memory_mmap(.hint = 0, .length = length, .protection = _posix_memory_read_write, .flags = _linux_private_anonymous, .file_descriptor = -1, .offset = 0).address
    if address + 1 == 0 {
        address = _memory_mmap(.hint = 0, .length = length, .protection = _posix_memory_read_write, .flags = _darwin_private_anonymous, .file_descriptor = -1, .offset = 0).address
    }
}

