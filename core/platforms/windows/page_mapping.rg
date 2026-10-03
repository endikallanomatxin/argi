#if target_os("windows") {
-- Windows retains the original reservation behind an aligned exposed range.
-- The native adapter stores its release metadata outside that range.
_memory_getpagesize() -> (.size: UIntNative) : ExternFunction
_memory_acquire_aligned(.length: UIntNative, .alignment: UIntNative) -> (.address: UIntNative) : ExternFunction
_memory_release_aligned(.address: UIntNative, .length: UIntNative) -> (.status: Int32) : ExternFunction

}
