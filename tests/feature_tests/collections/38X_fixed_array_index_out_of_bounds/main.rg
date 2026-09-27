main (.system: System) -> (.status_code: Int32) := {
    values :: [2]Int32 = (10, 20)
    index ::= length(.self = system.args).count + 1
    value ::= values[index]
    status_code = value
}
