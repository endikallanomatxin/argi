_WalkFrame: Type = (.directory: Directory, .path: Path, .depth: UIntNative)

_WalkFrame deinit(.self: $&_WalkFrame, .allocator: $&Allocator) -> () := {
    assume allocator
    deinit(.self = $&self&.directory)
    deinit(.self = $&self&.path)
}

WalkEntry: Type = (.path: Path, .info: FileMetadata, .depth: UIntNative)

-- Depth-first traversal owns one open directory per active level. Entries
-- own their paths. Native enumeration order is unspecified. Links/reparse
-- points are reported as other and never deliberately descended into; path
-- lookup races mean this is not a security boundary. Depth zero visits nothing.
DirectoryWalker: Type = (
    ._frames        : DynamicArray#(.t: _WalkFrame),
    ._filesystem    : &FileSystem,
    ._maximum_depth : UIntNative,
    ._ended         : Bool
)

DirectoryWalker init(
        .self          : &FileSystem = reach file_system,
        .path          : StringView,
        .maximum_depth : UIntNative  = 64,
        .allocator     : $&Allocator = reach allocator
    ) -> (
        .result : Errable#(.t: DirectoryWalker, .reasons: _FilesystemReasons)
    ) := {
    assume allocator
    frames ::= DynamicArray#(.t: _WalkFrame)(.capacity = 1)!

    if maximum_depth > 0 {
        owned ::= path_with_view(.view = path)!
        directory ::= Directory(.self = self, .path = path)!
        push_assume_capacity(
            .self  = $&frames
            .value = _WalkFrame(~directory, ~owned, 0)
        )
    }

    result = ..ok(
        ._frames        = ~frames
        ._filesystem    = self
        ._maximum_depth = maximum_depth
        ._ended         = false
    )
}

DirectoryWalker deinit(.self: $&DirectoryWalker, .allocator: $&Allocator) -> () := {
    assume allocator

    while length(&self&._frames).count > 0 {
        discarded ::= ~unwrap_or_abort(.value = pop(.self = $&self&._frames))
    }

    deinit(.self = $&self&._frames)
}

-- EOF is sticky. Errors are terminal and preserve all owners for cleanup.
next(
        .self      : $&DirectoryWalker,
        .allocator : $&Allocator        = reach allocator
    ) -> (
        .result : Errable#(.t: ?WalkEntry, .reasons: _FilesystemReasons)
    ) := {
    assume allocator

    if self&._ended {
        result = ..ok ..none
        return
    }

    self&._ended = true

    while length(&self&._frames).count > 0 {
        count ::= length(&self&._frames).count
        frame ::= unwrap_or_abort(.value = get_rw_ref(.self = $&self&._frames, .index = count - 1))
        match next($&frame&.directory)! {
            ..none { discarded ::= ~unwrap_or_abort(.value = pop(.self = $&self&._frames)) }
            ..some ~entry {
                parent ::= as_view(&frame&.path)
                name ::= as_view(&entry.value.name)
                path ::= join_views(.left = &parent, .right = &name)!
                text ::= as_view(&path)
                info ::= metadata(.self = self&._filesystem, .path = text, .follow_links = false)!
                depth ::= frame&.depth + 1
                directory_kind :: FileKind = ..directory
                if info.kind == directory_kind and depth < self&._maximum_depth {
                    ensure_capacity(
                        .self     = $&self&._frames
                        .capacity = count + 1
                    )!
                    owned ::= copy(.self = &path)!
                    directory ::= Directory(.self = self&._filesystem, .path = text)!
                    push_assume_capacity(
                        .self  = $&self&._frames
                        .value = _WalkFrame(~directory, ~owned, depth)
                    )
                }
                self&._ended = false
                result = ..ok ..some(.value = (.path = ~path, .info = info, .depth = depth))
                return
            }
        }
    }

    result = ..ok ..none
}
