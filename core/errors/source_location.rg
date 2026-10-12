-- Source IDs index immutable executable metadata; retaining a frame does not
-- retain reader strings or references to a context expression.
SourceLocationId: Type = (.value: UInt32)

implement ImplicitlyCopyable#(SourceLocationId) ()

SourceLocation: Type = (
    .source_file : &Char
    .source_line : &Char
    .line        : UIntNative
    .column      : UIntNative
)

implement ImplicitlyCopyable#(SourceLocation) ()

-- These two core operations are lowered to executable metadata by codegen.
error_location_id() -> (.location: SourceLocationId) := {
    location = (.value = 0)
}

source_location(.id: SourceLocationId) -> (.location: SourceLocation) := {
    location = (.source_file = "", .source_line = "", .line = 0, .column = 0)
}
