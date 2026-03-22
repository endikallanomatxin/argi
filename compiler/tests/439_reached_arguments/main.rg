read_value(
    .stdout: Int32 = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> (.value: Int32) := {
    value = stdout
}

forward() -> (.value: Int32) := {
    value = read_value()
}

main() -> (.status_code: Int32) := {
    system : (
        .terminal: (
            .stdout: Int32
        )
    ) = (
        .terminal = (
            .stdout = 7
        )
    )

    stdout :: Int32 = 9

    status_code = forward()
}
