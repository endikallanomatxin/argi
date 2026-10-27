check_fallible_result := () -> !Void = {}

main := (.system: System) -> (
    .status_code : Int32 = 1
) {
    assume writer ::= $&system.terminal&.stderr
    check_fallible_result()!!!
    status_code = 0
}
