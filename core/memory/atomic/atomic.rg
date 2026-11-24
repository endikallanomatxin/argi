_atomic_create(.initial: UInt32) -> (.handle: UIntNative): CFunction(
    .symbol = "_argi_atomic_u32_create"
)

_atomic_destroy(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_atomic_u32_destroy")

_atomic_load(.handle: UIntNative) -> (.value: UInt32): CFunction(
    .symbol = "_argi_atomic_u32_load"
) where { no_access() }

_atomic_store(.handle: UIntNative, .value: UInt32) -> (): CFunction(
    .symbol = "_argi_atomic_u32_store"
) where { no_access() }

_atomic_exchange(.handle: UIntNative, .value: UInt32) -> (.previous: UInt32): CFunction(
    .symbol = "_argi_atomic_u32_exchange"
) where { no_access() }

_atomic_add(.handle: UIntNative, .value: UInt32) -> (.previous: UInt32): CFunction(
    .symbol = "_argi_atomic_u32_fetch_add"
) where { no_access() }

_atomic_compare(.handle: UIntNative, .expected: UInt32, .desired: UInt32) -> (.packed: UInt64): CFunction(
    .symbol = "_argi_atomic_u32_compare_exchange"
) where { no_access() }

-- All operations use sequential consistency. Native storage is private and
-- stable across owner moves. The owner retains FFI permission and releases
-- the cell exactly once. Shared operations read the stable handle and call the
-- matching atomic primitive. ConcurrentAlias covers this native dependency.
AtomicUInt32 := (._handle: UIntNative, ._ffi: $&ForeignFunctionInterface)

implement ConcurrentAlias#(AtomicUInt32) ()

AtomicUInt32InitArgs: Type = (
    .initial : UInt32                     = 0,
    .ffi     : $&ForeignFunctionInterface
)

implement Init#(AtomicUInt32, AtomicUInt32InitArgs) (
    .Result : Type = Errable#(AtomicUInt32, (..out_of_memory))

    .init = AtomicUInt32InitArgs -> (.result: Result) {

        _init_initial ::= initial
        _init_ffi ::= ffi

        assume ffi := _init_ffi
        handle ::= _atomic_create(.initial = _init_initial).handle

        if handle == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }

        result = ..ok(._handle = handle, ._ffi = _init_ffi)
    }
)

implement Deinit#(AtomicUInt32) (
    .deinit = (.self: $&AtomicUInt32) -> () {
        assume ffi := self&._ffi
        _atomic_destroy(.handle = self&._handle)
    }
)

load := (.self: &AtomicUInt32) -> (.value: UInt32) {
    assume ffi := self&._ffi
    value = _atomic_load(.handle = self&._handle).value
}

store := (.self: $&AtomicUInt32, .value: UInt32) -> () {
    assume ffi := self&._ffi
    _atomic_store(.handle = self&._handle, .value = value)
}

exchange := (.self: $&AtomicUInt32, .value: UInt32) -> (.previous: UInt32) {
    assume ffi := self&._ffi
    previous = _atomic_exchange(.handle = self&._handle, .value = value).previous
}

-- Return the previous value; unsigned addition wraps modulo 2^32.
fetch_add := (.self: $&AtomicUInt32, .value: UInt32) -> (.previous: UInt32) {
    assume ffi := self&._ffi
    previous = _atomic_add(.handle = self&._handle, .value = value).previous
}

compare_exchange := (.self: $&AtomicUInt32, .expected: UInt32, .desired: UInt32) -> (
    .observed: UInt32, .swapped: Bool
) {

    assume ffi := self&._ffi
    packed ::= _atomic_compare(
        .handle = self&._handle, .expected = expected, .desired = desired
    ).packed
    observed = unwrap_or_abort(.value = [packed % 4294967296] | convert#(.to: UInt32)(_))
    swapped = packed / 4294967296 != 0
}

shared_fetch_add := (.self: $$&AtomicUInt32, .value: UInt32) -> (.previous: UInt32) {
    cell ::= trusted_concurrent_view(.shared = self)
    assume ffi := cell&._ffi
    previous = _atomic_add(.handle = cell&._handle, .value = value).previous
}

shared_load := (.self: $$&AtomicUInt32) -> (.value: UInt32) {
    cell ::= trusted_concurrent_view(.shared = self)
    assume ffi := cell&._ffi
    value = _atomic_load(.handle = cell&._handle).value
}

shared_store := (.self: $$&AtomicUInt32, .value: UInt32) -> () {
    cell ::= trusted_concurrent_view(.shared = self)
    assume ffi := cell&._ffi
    _atomic_store(.handle = cell&._handle, .value = value)
}

shared_exchange := (.self: $$&AtomicUInt32, .value: UInt32) -> (.previous: UInt32) {
    cell ::= trusted_concurrent_view(.shared = self)
    assume ffi := cell&._ffi
    previous = _atomic_exchange(.handle = cell&._handle, .value = value).previous
}

shared_compare_exchange := (.self: $$&AtomicUInt32, .expected: UInt32, .desired: UInt32) -> (
    .observed: UInt32, .swapped: Bool
) {

    cell ::= trusted_concurrent_view(.shared = self)
    assume ffi := cell&._ffi
    packed ::= _atomic_compare(
        .handle = cell&._handle, .expected = expected, .desired = desired
    ).packed
    observed = unwrap_or_abort(.value = [packed % 4294967296] | convert#(.to: UInt32)(_))
    swapped = packed / 4294967296 != 0
}
