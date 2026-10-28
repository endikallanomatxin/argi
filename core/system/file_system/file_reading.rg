-- Whole-file reading selects the path representation and allocation provider.
FileReading#(.PathValue: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .read_file : (.self: &FileSystem, .path: PathValue, .allocator: $&Provider) -> (
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

implement#(.Provider: Type: Allocator#(Provider)) FileReading#(&CChar, Provider) (
    .read_file = _read_c_file
)

implement#(.Provider: Type: Allocator#(Provider)) FileReading#(&String, Provider) (
    .read_file = _read_string_file
)

implement#(.Provider: Type: Allocator#(Provider)) FileReading#(StringView, Provider) (
    .read_file = _read_view_file
)

implement#(.Provider: Type: Allocator#(Provider)) FileReading#(&Path, Provider) (
    .read_file = _read_path_file
)
