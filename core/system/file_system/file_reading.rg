-- Whole-file reading selects the path representation and uses a virtual allocator.
FileReading#(.PathValue: Type): Contract = (
    .read_file : (.self: &FileSystem, .path: PathValue, .allocator: Virtual#(Allocator)) -> (
        .result : Errable#(
            String,
            (
                ..path_open_failed,
                ..stream_read_failed,
                ..invalid_utf8,
                ..stream_close_failed,
                ..out_of_memory
            )
        )
    )
)

implement FileReading#(&CChar) (
    .read_file = _read_c_file
)

implement FileReading#(&String) (
    .read_file = _read_string_file
)

implement FileReading#(StringView) (
    .read_file = _read_view_file
)

implement FileReading#(&Path) (
    .read_file = _read_path_file
)
