LeftSelection#(.Value: Type): Contract = (
    .pick : (.value: Value, .left: Int32 = 1) -> (.status_code: Int32)
)

RightSelection#(.Value: Type): Contract = (
    .pick : (.value: Value, .right: Int32 = 2) -> (.status_code: Int32)
)

_left_pick := (.value: Int32, .left: Int32 = 1) -> (.status_code: Int32) { status_code = left }

_right_pick := (.value: Int32, .right: Int32 = 2) -> (.status_code: Int32) {
    status_code = right
}

implement LeftSelection#(Int32) (.pick = _left_pick)

implement RightSelection#(Int32) (.pick = _right_pick)

main := () -> (.status_code: Int32) { status_code = pick(.value = 7).status_code }
