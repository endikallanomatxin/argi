-- Compiler-selected companion geometry, independent of value representation.
-- Preparing an acquisition reserves these ranges before publishing slot loans.
_AllocationMetadataLayout: Type = (
    .cleanup_flags    : UIntNative
    .reference_leaves : UIntNative
    .reference_bytes  : UIntNative
    .alignment        : UIntNative
)

-- Registered representation primitive. Both lowering paths supply the selected
-- type's immutable geometry; the ordinary signature carries no capabilities.
_allocation_metadata_layout#(.t: Type)() -> (.layout: _AllocationMetadataLayout) := {
    layout = (.cleanup_flags = 0, .reference_leaves = 0, .reference_bytes = 0, .alignment = 1)
}
