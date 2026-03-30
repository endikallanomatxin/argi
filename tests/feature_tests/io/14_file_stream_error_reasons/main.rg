main() -> (.status_code: Int32) := {
    file ::= File(.handle = 0, .should_close = 0 == 1)

    read_result ::= read_byte(.self = $&file)
    if is(.value = read_result, .variant = ..error) {
    } else {
        status_code = 1
        return
    }

    if is(.value = read_result..error.reason, .variant = ..stream_read_failed) {
    } else {
        status_code = 2
        return
    }

    write_result ::= write_byte(.self = $&file, .byte = 65)
    if is(.value = write_result, .variant = ..error) {
    } else {
        status_code = 3
        return
    }

    if is(.value = write_result..error.reason, .variant = ..stream_write_failed) {
    } else {
        status_code = 4
        return
    }

    flush_result ::= flush(.self = $&file)
    if is(.value = flush_result, .variant = ..error) {
    } else {
        status_code = 5
        return
    }

    if is(.value = flush_result..error.reason, .variant = ..stream_flush_failed) {
    } else {
        status_code = 6
        return
    }

    close_result ::= close(.self = $&file)
    if is(.value = close_result, .variant = ..ok) {
    } else {
        status_code = 7
        return
    }

    status_code = 0
}
