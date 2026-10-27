Source: Type = ()

implement Reader#(Source) (
    .read_byte = (.self: $&Source) -> (.result: Errable#(ReadByte, (..stream_read_failed))) {
        result = ..ok ..end
    }
)

make_reader := (.source: $&Source) -> (.result: BufferedReader#(Source)) {
    result = BufferedReader(.base = source)
}

main := () -> () {
    source :: Source = ()
    reader ::= make_reader($&source)
    _ ::= Reader#().read_byte($&reader)
}
