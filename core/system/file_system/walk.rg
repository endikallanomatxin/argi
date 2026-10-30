_WalkFrame := (.directory: Directory, .path: Path, .depth: UIntNative)

implement Deinit#(_WalkFrame) (
    .deinit = (.self: $&_WalkFrame) -> () {
        deinit(.self = $&self&.directory)
        deinit(.self = $&self&.path)
    }
)

WalkEntry := (.path: Path, .info: FileMetadata, .depth: UIntNative)

-- Depth-first traversal owns one open directory per active level. Entries
-- own their paths. Native enumeration order is unspecified. Links/reparse
-- points are reported as other and never deliberately descended into; path
-- lookup races mean this is not a security boundary. Depth zero visits nothing.
DirectoryWalker := (
    ._frames        : DynamicArray#(.t: _WalkFrame),
    ._filesystem    : &FileSystem,
    ._maximum_depth : UIntNative,
    ._ended         : Bool
)

DirectoryWalkerInitArgs: Type = #(.Provider: Type: Allocator) (
    .self          : &FileSystem,
    .path          : StringView,
    .maximum_depth : UIntNative   = 64,
    .allocator     : $&Provider
)

implement#(.Provider: Type: Allocator) Init#(
    DirectoryWalker, DirectoryWalkerInitArgs#(Provider)
) (
    .Result : Type = Errable#(DirectoryWalker, _FilesystemReasons)

    .init = DirectoryWalkerInitArgs#(Provider) -> (.result: Result) {

        _init_self ::= self
        _init_path ::= path
        _init_maximum_depth ::= maximum_depth
        _init_allocator ::= allocator

        assume allocator := _init_allocator
        frames ::= DynamicArray#(.t: _WalkFrame)(.capacity = 1)!

        if _init_maximum_depth > 0 {
            owned ::= path_with_view(.view = _init_path)!
            directory ::= Directory(.self = _init_self, .path = _init_path)!
            push_assume_capacity($&frames, .value = _WalkFrame(~directory, ~owned, 0))
        }

        result = ..ok(
            ._frames        = ~frames
            ._filesystem    = _init_self
            ._maximum_depth = _init_maximum_depth
            ._ended         = false
        )
    }
)

implement Deinit#(DirectoryWalker) (
    .deinit = (.self: $&DirectoryWalker) -> () {

        while length(&self&._frames).count > 0 {
            discarded ::= ~unwrap_or_abort(.value = pop($&self&._frames))
        }

        deinit(.self = $&self&._frames)
    }
)

-- EOF is sticky. Errors are terminal and preserve all owners for cleanup.
_next_directory_walker := #(.Provider: Type: Allocator#(Provider)) (
    .self: $&DirectoryWalker, .allocator: $&Provider
) -> (.result: Errable#(?WalkEntry, _FilesystemReasons)) {

    assume allocator

    if self&._ended {
        result = ..ok ..none
        return
    }

    self&._ended = true

    while length(&self&._frames).count > 0 {
        count ::= length(&self&._frames).count
        frame ::= unwrap_or_abort(
            .value = get_mutable_reference($&self&._frames, .index = [count - 1])
        )
        match next($&frame&.directory)! {
            ..none { discarded ::= ~unwrap_or_abort(.value = pop($&self&._frames)) }
            ..some ~entry {
                parent ::= view(&frame&.path)
                name ::= view(&entry.value.name)
                path ::= join_views(.left = &parent, .right = &name)!
                text ::= view(&path)
                info ::= metadata(self&._filesystem, .path = text, .follow_links = false)!
                depth ::= frame&.depth + 1
                if info.kind == ..directory and depth < self&._maximum_depth {
                    ensure_capacity(.self = $&self&._frames, .capacity = count + 1)!
                    owned ::= copy(&path, .allocator = allocator)!
                    directory ::= Directory(.self = self&._filesystem, .path = text)!
                    push_assume_capacity(
                        $&self&._frames, .value = _WalkFrame(~directory, ~owned, depth)
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
