_atomic_create(.initial: UInt32) -> (.handle: UIntNative): CFunction(
    .symbol = "_argi_atomic_u32_create"
)

_atomic_destroy(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_atomic_u32_destroy")

_atomic_load(.handle: UIntNative) -> (.value: UInt32): CFunction(.symbol = "_argi_atomic_u32_load")

_atomic_store(.handle: UIntNative, .value: UInt32) -> (): CFunction(
    .symbol = "_argi_atomic_u32_store"
)

_atomic_exchange(.handle: UIntNative, .value: UInt32) -> (.previous: UInt32): CFunction(
    .symbol = "_argi_atomic_u32_exchange"
)

_atomic_add(.handle: UIntNative, .value: UInt32) -> (.previous: UInt32): CFunction(
    .symbol = "_argi_atomic_u32_fetch_add"
)

_atomic_compare(.handle: UIntNative, .expected: UInt32, .desired: UInt32) -> (.packed: UInt64): CFunction(
    .symbol = "_argi_atomic_u32_compare_exchange"
)

-- All operations use sequential consistency. Native storage is private and
-- stable across owner moves. The owner retains FFI permission and releases
-- the cell exactly once. This does not authorize transferring Argi references
-- across threads; that requires the language's separate transfer contracts.
AtomicUInt32: Type = (._handle: UIntNative, ._ffi: $&ForeignFunctionInterface)

AtomicUInt32 init(
        .initial : UInt32                     = 0,
        .ffi     : $&ForeignFunctionInterface = reach ffi
    ) -> (
        .result : Errable#(.t: AtomicUInt32, .reasons: (..out_of_memory))
    ) := {
    assume ffi
    handle ::= _atomic_create(.initial = initial).handle
    if handle == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = ..ok(._handle = handle, ._ffi = ffi)
}

AtomicUInt32 deinit(.self: $&AtomicUInt32) -> () := {
    assume ffi := self&._ffi
    _atomic_destroy(.handle = self&._handle)
}

load(.self: &AtomicUInt32) -> (.value: UInt32) := {
    assume ffi := self&._ffi
    value = _atomic_load(.handle = self&._handle).value
}

store(.self: $&AtomicUInt32, .value: UInt32) -> () := {
    assume ffi := self&._ffi
    _atomic_store(.handle = self&._handle, .value = value)
}

exchange(.self: $&AtomicUInt32, .value: UInt32) -> (.previous: UInt32) := {
    assume ffi := self&._ffi
    previous = _atomic_exchange(.handle = self&._handle, .value = value).previous
}

-- Return the previous value; unsigned addition wraps modulo 2^32.
fetch_add(.self: $&AtomicUInt32, .value: UInt32) -> (.previous: UInt32) := {
    assume ffi := self&._ffi
    previous = _atomic_add(.handle = self&._handle, .value = value).previous
}

compare_exchange(
        .self     : $&AtomicUInt32,
        .expected : UInt32,
        .desired  : UInt32
    ) -> (
        .observed : UInt32,
        .swapped  : Bool
    ) := {
    assume ffi := self&._ffi
    packed ::= _atomic_compare(.handle = self&._handle, .expected = expected, .desired = desired).packed
    observed = unwrap_or_abort(.value = UInt32(.value = packed % 4294967296))
    swapped = packed / 4294967296 != 0
}
