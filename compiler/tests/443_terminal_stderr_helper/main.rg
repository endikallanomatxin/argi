DummyOutput : Type = (
    .write_count: Int32 = 0
    .flush_count: Int32 = 0
)

write(.self: $&DummyOutput, .text: String) -> () := {
    self& = (
        .write_count = self&.write_count + 1,
        .flush_count = self&.flush_count,
    )
}

flush(.self: $&DummyOutput) -> () := {
    self& = (
        .write_count = self&.write_count,
        .flush_count = self&.flush_count + 1,
    )
}

DummyOutput implements OutputStream#(.text: String)

main(.system: System) -> (.status_code: Int32) := {
    allocator ::= system.allocator
    stderr :: DummyOutput = (
        .write_count = 0,
        .flush_count = 0,
    )
    text ::= String(.length = 0)

    print_error(.stderr = $&stderr, .text = text)
    flush_error(.stderr = $&stderr)

    status_code = stderr.write_count * 10 + stderr.flush_count
}
