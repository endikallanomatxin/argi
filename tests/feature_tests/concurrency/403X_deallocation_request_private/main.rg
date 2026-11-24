main := () -> () {
    request: Deallocation = (
        ._data = raw_pointer#(UInt8)(.address = 0).raw
        ._size = 0
        ._alignment = 1
    )
}
