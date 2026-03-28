read_value(
    .stdout: Int32 = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> (.value: Int32) := {
    value = stdout
}

forward() -> (.value: Int32) := {
    value = read_value()
}

main() -> (.status_code: Int32) := {
    status_code = forward()
}
