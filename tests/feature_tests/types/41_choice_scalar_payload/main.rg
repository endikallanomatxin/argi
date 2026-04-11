MaybeInt : Type = (
    ..none
    ..some Int32
)

main() -> (.status_code: Int32 = 0) := {
    a : MaybeInt = ..none
    b : MaybeInt = ..some 123

    match a {
        ..none {
        }
        ..some _ {
            status_code = 1
            return
        }
    }

    match b {
        ..none {
            status_code = 2
            return
        }
        ..some n {
            if n != 123 {
                status_code = 3
                return
            }
        }
    }

    n ::= b..some
    if n != 123 {
        status_code = 4
        return
    }

    if b == ..none {
        status_code = 5
        return
    }

    if b != ..some {
        status_code = 6
        return
    }
}
