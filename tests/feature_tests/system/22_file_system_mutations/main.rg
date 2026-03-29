main(.system: System = System()) -> (.status_code: Int32) := {
    src_path ::= from_literal(.data = "tests/feature_tests/system/22_file_system_mutations/build/temp_src.txt")
    dst_path ::= from_literal(.data = "tests/feature_tests/system/22_file_system_mutations/build/temp_dst.txt")

    if exists(.self = system.file_sys, .path = src_path).ok {
        removed_src ::= remove(.self = system.file_sys, .path = src_path)
        if is(.value = removed_src, .variant = ..ok) {
        } else {
            status_code = 1
            return
        }
    }

    if exists(.self = system.file_sys, .path = dst_path).ok {
        removed_dst ::= remove(.self = system.file_sys, .path = dst_path)
        if is(.value = removed_dst, .variant = ..ok) {
        } else {
            status_code = 2
            return
        }
    }

    if exists(.self = system.file_sys, .path = src_path).ok {
        status_code = 3
        return
    }

    created_file_result ::= open_write(.self = system.file_sys, .path = src_path)
    if is(.value = created_file_result, .variant = ..ok) {
    } else {
        status_code = 4
        return
    }
    created_file ::= created_file_result..ok.value
    close(.self = $&created_file)

    if exists(.self = system.file_sys, .path = src_path).ok {
    } else {
        status_code = 5
        return
    }

    renamed ::= rename(.self = system.file_sys, .from = src_path, .to = dst_path)
    if is(.value = renamed, .variant = ..ok) {
    } else {
        status_code = 6
        return
    }

    if exists(.self = system.file_sys, .path = src_path).ok {
        status_code = 7
        return
    }

    if exists(.self = system.file_sys, .path = dst_path).ok {
    } else {
        status_code = 8
        return
    }

    removed_final ::= remove(.self = system.file_sys, .path = dst_path)
    if is(.value = removed_final, .variant = ..ok) {
    } else {
        status_code = 9
        return
    }

    if exists(.self = system.file_sys, .path = dst_path).ok {
        status_code = 10
        return
    }

    status_code = 0
}
