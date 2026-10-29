-- Enumeration copies each native name before advancing its directory handle.
DirectoryEnumeration#(.State: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Item   : Type
    .Result : Type
    .next   : (.self: $&State, .allocator: $&Provider, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Result
    )
)

implement#(.Provider: Type: Allocator#(Provider)) DirectoryEnumeration#(Directory, Provider) (
    .Item   : Type = DirectoryEntry
    .Result : Type = Errable#(Nullable#(.t: DirectoryEntry), _FilesystemReasons)
    .next   = _next_directory
)

implement#(.Provider: Type: Allocator#(Provider)) DirectoryEnumeration#(
    DirectoryWalker, Provider
) (
    .Item   : Type = WalkEntry
    .Result : Type = Errable#(?WalkEntry, _FilesystemReasons)
    .next   = _next_directory_walker
)
