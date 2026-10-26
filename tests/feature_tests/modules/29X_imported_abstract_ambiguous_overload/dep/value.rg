LeftSelection<.Value: Type>: Contract = (
    .pick : (.value: Value, .left: Int32 = 0) -> (.result: Int32)
)

RightSelection<.Value: Type>: Contract = (
    .pick : (.value: Value, .right: Int32 = 0) -> (.result: Int32)
)

_left_pick := (.value: Int32, .left: Int32 = 0) -> (.result: Int32) { result = 1 }

_right_pick := (.value: Int32, .right: Int32 = 0) -> (.result: Int32) { result = 2 }

implement LeftSelection<Int32> (.pick = _left_pick)

implement RightSelection<Int32> (.pick = _right_pick)
