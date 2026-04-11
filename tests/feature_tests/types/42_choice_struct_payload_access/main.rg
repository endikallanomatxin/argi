SpanOrEnd : Type = (
    ..end
    ..span (.start: UIntNative, .end: UIntNative)
)

main() -> (.status_code: Int32 = 0) := {
    c : SpanOrEnd = ..span (.start = 3, .end = 8)

    match c {
        ..end {
            status_code = 1
            return
        }
        ..span s {
            if s.start != 3 {
                status_code = 2
                return
            }
            if s.end != 8 {
                status_code = 3
                return
            }
        }
    }

    s ::= c..span
    if s.start != 3 {
        status_code = 4
        return
    }

    if c..span.start != 3 {
        status_code = 5
        return
    }
}
