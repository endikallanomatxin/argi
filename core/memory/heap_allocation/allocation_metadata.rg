-- Compiler-selected companion geometry, independent of value representation.
-- Preparing an acquisition reserves these ranges before publishing slot loans.
_AllocationMetadataLayout := (
    .cleanup_flags    : UIntNative
    .reference_leaves : UIntNative
    .reference_bytes  : UIntNative
    .alignment        : UIntNative
    .header_bytes     : UIntNative
)

-- Registered representation primitive. Both lowering paths supply the selected
-- type's immutable geometry; the ordinary signature carries no capabilities.
_allocation_metadata_layout := <.t: Type> () -> (.layout: _AllocationMetadataLayout) {
    layout = (
        .cleanup_flags    = 0
        .reference_leaves = 0
        .reference_bytes  = 0
        .alignment        = 1
        .header_bytes     = 0
    )
}

-- Preparation returns a private backend-local handle, never a data address
-- usable as a language reference or proof of initialized values.
_prepare_allocation_metadata := <.t: Type> (.allocation: &Allocation) -> (.state: UIntNative) {
    state = 0
}
