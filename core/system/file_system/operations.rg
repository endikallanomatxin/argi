..invalid_path
..path_not_found
..permission_denied
..already_exists
..not_a_directory
..filesystem_failed

_FilesystemReasons: Type = (
    ..invalid_path,
    ..path_not_found,
    ..permission_denied,
    ..already_exists,
    ..not_a_directory,
    ..filesystem_failed,
    ..out_of_memory
)

_fs_reason(.status: Int32) -> (.reason: _FilesystemReasons) := {
    reason = ..filesystem_failed

    if status == -2 { reason = ..invalid_path }
    if status == -3 { reason = ..out_of_memory }
    if status == -4 { reason = ..path_not_found }
    if status == -5 { reason = ..permission_denied }
    if status == -6 { reason = ..already_exists }
    if status == -7 { reason = ..not_a_directory }
}

_fs_mkdir(.bytes: &UInt8, .length: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_mkdir"
)

_fs_rmdir(.bytes: &UInt8, .length: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_rmdir"
)

_fs_metadata(
        .bytes       : &UInt8,
        .length      : UIntNative,
        .kind        : $&Int32,
        .size        : $&UInt64,
        .seconds     : $&Int64,
        .nanoseconds : $&UInt32
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_fs_metadata")

_fs_metadata_nofollow(
        .bytes       : &UInt8,
        .length      : UIntNative,
        .kind        : $&Int32,
        .size        : $&UInt64,
        .seconds     : $&Int64,
        .nanoseconds : $&UInt32
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_fs_metadata_nofollow")

_fs_directory_open(.bytes: &UInt8, .length: UIntNative, .handle: $&UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_directory_open"
)

_fs_directory_next(.handle: UIntNative, .length: $&UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_directory_next"
)

_fs_directory_copy(.handle: UIntNative, .bytes: $&UInt8, .capacity: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_directory_copy"
)

_fs_directory_close(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_fs_directory_close")

_fs_seek(
        .stream   : UIntNative,
        .offset   : Int64,
        .origin   : Int32,
        .position : $&UInt64
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_fs_seek")

_fs_truncate(.stream: UIntNative, .size: UInt64) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_truncate"
)

create_directory(
        .self : &FileSystem = reach file_system,
        .path : StringView
    ) -> (
        .result : Errable#(Void, _FilesystemReasons)
    ) := {
    assume ffi := self&._ffi
    status ::= _fs_mkdir(.bytes = path.data, .length = path.length).status

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    result = ..ok Void()
}

remove_directory(
        .self : &FileSystem = reach file_system,
        .path : StringView
    ) -> (
        .result : Errable#(Void, _FilesystemReasons)
    ) := {
    assume ffi := self&._ffi
    status ::= _fs_rmdir(.bytes = path.data, .length = path.length).status

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    result = ..ok Void()
}

FileKind: Type = (..file, ..directory, ..other)

FileKind implements ImplicitlyCopyable

FileMetadata: Type = (.kind: FileKind, .size: UInt64, .modified: UnixTimestamp)

FileMetadata implements ImplicitlyCopyable

metadata(
        .self         : &FileSystem = reach file_system,
        .path         : StringView,
        .follow_links : Bool        = true
    ) -> (
        .result : Errable#(FileMetadata, _FilesystemReasons)
    ) := {
    assume ffi := self&._ffi
    kind :: Int32 = 0
    size :: UInt64 = 0
    seconds :: Int64 = 0
    nanoseconds :: UInt32 = 0
    status :: Int32 = 0

    if follow_links {
        status = _fs_metadata(
            .bytes       = path.data
            .length      = path.length
            .kind        = $&kind
            .size        = $&size
            .seconds     = $&seconds
            .nanoseconds = $&nanoseconds
        ).status
    } else {
        status = _fs_metadata_nofollow(
            .bytes       = path.data
            .length      = path.length
            .kind        = $&kind
            .size        = $&size
            .seconds     = $&seconds
            .nanoseconds = $&nanoseconds
        ).status
    }

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    selected :: FileKind = ..other

    if kind == 1 { selected = ..file }
    if kind == 2 { selected = ..directory }
    modified ::= unwrap_or_abort(
        .value = UnixTimestamp(.seconds = seconds, .nanoseconds = nanoseconds)
    )

    result = ..ok(.kind = selected, .size = size, .modified = modified)
}

-- Enumeration copies names into independent owners, never borrowed dirent data.
Directory: Type = (._filesystem: &FileSystem, ._handle: UIntNative, ._ended: Bool)

DirectoryEntry: Type = (.name: String)

Directory init(
        .self : &FileSystem = reach file_system,
        .path : StringView
    ) -> (
        .result : Errable#(Directory, _FilesystemReasons)
    ) := {
    assume ffi := self&._ffi
    handle :: UIntNative = 0
    status ::= _fs_directory_open(.bytes = path.data, .length = path.length, .handle = $&handle).status

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    result = ..ok(._filesystem = self, ._handle = handle, ._ended = false)
}

next(
        .self      : $&Directory,
        .allocator : $&Allocator  = reach allocator
    ) -> (
        .result : Errable#(Nullable#(.t: DirectoryEntry), _FilesystemReasons)
    ) := {
    assume ffi := self&._filesystem&._ffi
    assume allocator

    if self&._ended {
        result = ..ok ..none
        return
    }

    size :: UIntNative = 0
    status ::= _fs_directory_next(.handle = self&._handle, .length = $&size).status

    if status == 1 {
        self&._ended = true
        result = ..ok ..none
        return
    }

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    name ::= string_with_length(.allocator = allocator, .length = size)!

    if size > 0 {
        copied ::= _fs_directory_copy(
            .handle   = self&._handle
            .bytes    = _trusted_allocation_byte_rw(.allocation = $&name.allocation, .offset = 0).reference
            .capacity = size
        ).status
        if copied != 0 {
            result = ..error(.reason = _fs_reason(.status = copied).reason)
            return
        }
    }

    result = ..ok ..some(.value = (.name = ~name))
}

Directory deinit(.self: $&Directory) -> () := {
    assume ffi := self&._filesystem&._ffi
    _fs_directory_close(.handle = self&._handle)
}

SeekOrigin: Type = (..start, ..current, ..end)

SeekOrigin implements ImplicitlyCopyable
..stream_seek_failed
..stream_truncate_failed

seek(
        .self   : $&File,
        .offset : Int64,
        .origin : SeekOrigin
    ) -> (
        .result : Errable#(UInt64, (..stream_seek_failed))
    ) := {
    assume ffi := self&._ffi
    selected :: Int32 = 0

    if origin == ..current { selected = 1 }
    if origin == ..end { selected = 2 }
    position :: UInt64 = 0

    if [
        _fs_seek(
            .stream   = self&.stream_address
            .offset   = offset
            .origin   = selected
            .position = $&position
        ).status
        != 0
    ] {
        result = ..error(.reason = ..stream_seek_failed)
        return
    }

    result = ..ok position
}

position(.self: $&File) -> (.result: Errable#(UInt64, (..stream_seek_failed))) := {
    result = seek(self, .offset = 0, .origin = ..current)
}

truncate(
        .self : $&File,
        .size : UInt64
    ) -> (
        .result : Errable#(Void, (..stream_truncate_failed))
    ) := {
    assume ffi := self&._ffi

    if _fs_truncate(.stream = self&.stream_address, .size = size).status != 0 {
        result = ..error(.reason = ..stream_truncate_failed)
        return
    }

    result = ..ok Void()
}

_fs_temp_create(
        .parent        : &UInt8,
        .parent_length : UIntNative,
        .prefix        : &UInt8,
        .prefix_length : UIntNative,
        .handle        : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_fs_temp_create")

_fs_temp_length(.handle: UIntNative) -> (.length: UIntNative): CFunction(
    .symbol = "_argi_fs_temp_length"
)

_fs_temp_copy(.handle: UIntNative, .bytes: $&UInt8, .capacity: UIntNative) -> (.status: Int32): CFunction(
    .symbol = "_argi_fs_temp_copy"
)

_fs_temp_close(.handle: UIntNative) -> (.status: Int32): CFunction(.symbol = "_argi_fs_temp_close")

_fs_temp_cleanup(.handle: UIntNative) -> (): CFunction(.symbol = "_argi_fs_temp_cleanup")

TemporaryDirectory: Type = (._filesystem: &FileSystem, ._handle: UIntNative, ._path: String)

TemporaryDirectory init(
        .self      : &FileSystem = reach file_system,
        .parent    : StringView,
        .prefix    : StringView  = "argi-",
        .allocator : $&Allocator = reach allocator
    ) -> (
        .result : Errable#(TemporaryDirectory, _FilesystemReasons)
    ) := {
    assume ffi := self&._ffi
    assume allocator
    handle :: UIntNative = 0
    status ::= _fs_temp_create(
        .parent        = parent.data
        .parent_length = parent.length
        .prefix        = prefix.data
        .prefix_length = prefix.length
        .handle        = $&handle
    ).status

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    count ::= _fs_temp_length(.handle = handle).length

    match string_with_length(.allocator = allocator, .length = count) {
        ..error _ {
            _fs_temp_cleanup(.handle = handle)
            result = ..error(.reason = ..out_of_memory)
        }
        ..ok ~name {
            target ::= _trusted_allocation_byte_rw(.allocation = $&name.allocation, .offset = 0).reference
            if _fs_temp_copy(.handle = handle, .bytes = target, .capacity = count).status != 0 {
                _fs_temp_cleanup(.handle = handle)
                result = ..error(.reason = ..filesystem_failed)
                return
            }
            result = ..ok(._filesystem = self, ._handle = handle, ._path = ~name)
        }
    }
}

path(.self: &TemporaryDirectory) -> (.view: StringView) := {
    view = as_view(&self&._path).view
}

close(.self: $&TemporaryDirectory) -> (.result: Errable#(Void, _FilesystemReasons)) := {
    assume ffi := self&._filesystem&._ffi
    status ::= _fs_temp_close(.handle = self&._handle).status

    if status != 0 {
        result = ..error(.reason = _fs_reason(.status = status).reason)
        return
    }

    self&._handle = 0

    result = ..ok Void()
}

TemporaryDirectory deinit(
        .self      : $&TemporaryDirectory,
        .allocator : $&Allocator           = reach allocator
    ) -> () := {
    assume ffi := self&._filesystem&._ffi
    _fs_temp_cleanup(.handle = self&._handle)
    deinit(.self = $&self&._path, .allocator = allocator)
}
