-- Enumeration copies each native name before advancing its directory handle.
DirectoryEnumeration#(.State: Type): Contract = (
    .Item   : Type
    .Result : Type
    .next   : (.self: $&State, .allocator: $&Virtual#(Allocator)) -> (.result: Result)
)

implement DirectoryEnumeration#(Directory) (
    .Item   : Type = DirectoryEntry
    .Result : Type = Errable#(Nullable#(.t: DirectoryEntry), _FilesystemReasons)
    .next   = _next_directory
)

implement DirectoryEnumeration#(
    DirectoryWalker
) (
    .Item   : Type = WalkEntry
    .Result : Type = Errable#(?WalkEntry, _FilesystemReasons)
    .next   = _next_directory_walker
)
