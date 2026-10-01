read_value(
    .writer: Int32 = reach writer, terminal.writer, system.terminal.writer,
) -> (.value: Int32) := {
    value = writer
}

forward() -> (.value: Int32) := {
    value = read_value()
}

main() -> (.status_code: Int32) := {
    system : (
        .terminal: (
            .writer: Int32
        )
    ) = (
        .terminal = (
            .writer = 7
        )
    )

    writer :: Int32 = 9

    status_code = forward()
}
