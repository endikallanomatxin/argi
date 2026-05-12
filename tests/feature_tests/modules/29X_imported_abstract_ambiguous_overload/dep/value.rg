A : Abstract = ()

Int32 implements A

pick(
    .value: A,
    .left: Int32 = 0,
) -> (.result: Int32) := {
    result = 1
}

pick(
    .value: A,
    .right: Int32 = 0,
) -> (.result: Int32) := {
    result = 2
}
