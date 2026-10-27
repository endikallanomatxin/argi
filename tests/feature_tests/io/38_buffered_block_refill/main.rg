Source := (.count: UIntNative)

implement Reader#(Source) (
    .read_byte = (.self: $&Source) -> (
        .result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) {
        if self&.count == 4 {
            result = ..ok ..end
            return
        }
        self&.count = self&.count + 1
        result = ..ok ..ok 65
    }
)

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    source :: Source = (.count = 0)
    storage: [3]UInt8 = (0, 0, 0)
    reader ::= BufferedReader(.base = $&source, .buffer = view($&storage))
    match Reader#().read_byte(.self = $&reader)!!! {
        ..end { abort } ..ok byte { if byte != 65 { abort } }
    }
    if source.count != 3 { abort }
    match Reader#().read_byte(.self = $&reader)!!! { ..end { abort } ..ok byte {} }
    if source.count != 3 { abort }
    bytes :: [2]UInt8 = (0, 0)
    read_exact(.self = $&reader, .buffer = view(.self = $&bytes))!!!
    if source.count != 4 or bytes[0] != 65 or bytes[1] != 65 { abort }
    match Reader#().read_byte(.self = $&reader)!!! { ..end {} ..ok byte { abort } }
    status_code = 0
}
