first := 1; second := 2;

noop := () -> () { return; }

main := () -> (.status_code: Int32 = 0) {
    value ::= first; value = value + second;
    if value == 3 { noop(); value = value + 1; }
    text := ";"; -- ; remains part of the comment
    if text != ";" { return 1; }
    if value != 4 { return 2; }
    return 0;
}
