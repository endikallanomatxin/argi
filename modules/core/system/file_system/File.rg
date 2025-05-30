FileHandle : Abstract = [
    read_all(&_)        -> Array<Byte>
    write($&_, data: []Byte) -> Void
    seek($&_, pos: Int) -> Void
    flush($&_)          -> Void
    close($&_)          -> Void
]

