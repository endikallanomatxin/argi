..ok
..error

Fake: Type = (..ok Int32, ..error Int32)

main() -> () := {
    input: Fake = ..ok 7
    result ::= input handle value, error { value = 0 }
}
