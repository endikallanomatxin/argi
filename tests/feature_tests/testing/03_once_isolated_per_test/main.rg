once setup() -> () := {
}

helper() -> () := {
    setup()
}

test first(.system: System = System()) -> !() := {
    helper()
}

test second(.system: System = System()) -> !() := {
    helper()
}
