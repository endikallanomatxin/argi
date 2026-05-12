main(.system: System) -> (.status_code: Int32) := {
    stdin_alias_address :: UIntNative = cast#(.to: UIntNative)(.value = system.terminal&.stdin)
    stdin_reader_address :: UIntNative = cast#(.to: UIntNative)(.value = system.terminal&.stdin_reader)
    stdout_alias_address :: UIntNative = cast#(.to: UIntNative)(.value = system.terminal&.stdout)
    stdout_writer_address :: UIntNative = cast#(.to: UIntNative)(.value = system.terminal&.stdout_writer)
    stderr_alias_address :: UIntNative = cast#(.to: UIntNative)(.value = system.terminal&.stderr)
    stderr_file_address :: UIntNative = cast#(.to: UIntNative)(.value = system.terminal&.stderr_file)

    if stdin_alias_address != stdin_reader_address {
        status_code = 1
        return
    }

    if stdout_alias_address != stdout_writer_address {
        status_code = 2
        return
    }

    if stderr_alias_address != stderr_file_address {
        status_code = 3
        return
    }

    status_code = 0
}
