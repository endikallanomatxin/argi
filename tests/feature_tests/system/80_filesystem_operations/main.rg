main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    directory_path: StringView = "tests/feature_tests/system/80_filesystem_operations/build/sample"
    create_directory(.path = directory_path)!
    match create_directory(.path = directory_path) {
        ..ok _ { abort } ..error error { if [
                error.reason
                != ..already_exists
            ] { abort } }
    }
    info ::= metadata(.path = directory_path)!
    if info.kind != ..directory { abort }
    file_path: StringView = "tests/feature_tests/system/80_filesystem_operations/build/sample/bytes.bin"
    file ::= open_write(.self = file_system, .path = file_path, .allocator = allocator)!
    input: [4]UInt8 = (65, 0, 66, 67)
    write_all(.self = $&file, .buffer = view(.array = &input))!
    if position(.self = $&file)! != 4 { abort }
    if seek(.self = $&file, .offset = 1, .origin = ..start)! != 1 { abort }
    truncate(.self = $&file, .size = 2)!
    close(.self = $&file)!
    data ::= metadata(.path = file_path)!
    if data.kind != ..file or data.size != 2 { abort }
    directory ::= Directory(.path = directory_path)!
    entry ::= next(.self = $&directory)!
    match entry {
        ..none { abort }
        ..some ~payload { if as_view(.self = &payload.value.name).view != "bytes.bin" { abort } }
    }
    match next(.self = $&directory)! { ..some ~payload { abort } ..none {} }
    match next(.self = $&directory)! { ..some ~payload { abort } ..none {} }
    deinit(.self = $&directory)
    remove(.self = file_system, .path = file_path, .allocator = allocator)!
    remove_directory(.path = directory_path)!
    match metadata(.path = directory_path) {
        ..ok _ { abort } ..error error { if [
                error.reason
                != ..path_not_found
            ] { abort } }
    }
    invalid: [3]UInt8 = (97, 0, 98)
    invalid_path: StringView = (.data = &invalid[0], .length = 3)
    match create_directory(.path = invalid_path) {
        ..ok _ { abort } ..error error { if [
                error.reason
                != ..invalid_path
            ] { abort } }
    }
}
