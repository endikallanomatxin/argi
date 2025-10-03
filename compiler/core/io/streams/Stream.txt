InputStream : Abstract = [
    read(&_, buf: &mut ByteSlice) -> Int
    read_line(&_)                 -> String
]

OutputStream : Abstract = [
    write($&_, data: ByteSlice)   -> Int
    write_line($&_, data: String) -> Int
]
