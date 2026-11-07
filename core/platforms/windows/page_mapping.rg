#if target_os("windows") {
    -- Windows retains the original reservation behind an aligned exposed range.
    -- The native adapter stores its release metadata outside that range.
    _memory_getpagesize() -> (.size: UIntNative): ExternFunction
    _memory_acquire_aligned(.length: UIntNative, .alignment: UIntNative) -> (
        .address : UIntNative
    ): ExternFunction
    _memory_acquire_storage := (
        .length: UIntNative, .alignment: UIntNative, .ffi: $&ForeignFunctionInterface
    ) -> (.result: Errable#(AcquiredStorage, (..out_of_memory))) {
        assume ffi
        address ::= _memory_acquire_aligned(.length = length, .alignment = alignment).address
        if address + 1 == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        result = ..ok(._address = address, ._size = length, ._alignment = alignment)
    }

    _memory_release_aligned(.address: UIntNative, .length: UIntNative) -> (.status: Int32): ExternFunction

}
