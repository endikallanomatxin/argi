main(.system: System = System()) -> (.status_code: Int32) := {
    src_path ::= from_literal(.data = "tests/488_file_system_mutations/build/temp_src.txt")
    dst_path ::= from_literal(.data = "tests/488_file_system_mutations/build/temp_dst.txt")

    if exists(.self = system.file_sys, .path = src_path).ok {
        if remove(.self = system.file_sys, .path = src_path).ok {
        } else {
            status_code = 1
            return
        }
    }

    if exists(.self = system.file_sys, .path = dst_path).ok {
        if remove(.self = system.file_sys, .path = dst_path).ok {
        } else {
            status_code = 2
            return
        }
    }

    if exists(.self = system.file_sys, .path = src_path).ok {
        status_code = 3
        return
    }

    created_file ::= open_write(.self = system.file_sys, .path = src_path)
    close(.self = $&created_file)

    if exists(.self = system.file_sys, .path = src_path).ok {
    } else {
        status_code = 4
        return
    }

    if rename(.self = system.file_sys, .from = src_path, .to = dst_path).ok {
    } else {
        status_code = 5
        return
    }

    if exists(.self = system.file_sys, .path = src_path).ok {
        status_code = 6
        return
    }

    if exists(.self = system.file_sys, .path = dst_path).ok {
    } else {
        status_code = 7
        return
    }

    if remove(.self = system.file_sys, .path = dst_path).ok {
    } else {
        status_code = 8
        return
    }

    if exists(.self = system.file_sys, .path = dst_path).ok {
        status_code = 9
        return
    }

    status_code = 0
}
