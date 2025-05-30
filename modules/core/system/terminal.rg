Terminal : Type = [
    .stdin  :  & io.InputStream,
    .stdout : $& io.OutputStream,
    .stderr : $& io.OutputStream,
]

print($&Terminal, message: String) : Void {
    ...
}

println($&Terminal, message: String) : Void {
    ...
}

read_line($&Terminal) : String? {
    ...
}

read_char($&Terminal) : Char? {
    ...
}

set_buffering($&Terminal, mode: BufferMode) : Void {
    ...
}

set_echo($&Terminal, mode: BufferMode) : Void {
    ...
}

flush($&Terminal) : Void {
    ...
}

