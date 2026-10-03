identity#(.t: Type)(.value: t) -> (.result: t) := {
    result = [value]
}
Point : Type = (.x: Int32)
main() -> (.status_code: Int32 = 0) := {
    a :: Int32 = 2
    b :: Int32 = 3
    c :: Int32 = 4
    if [a + b] * c != 20 { status_code = 1 }
    if a * [b + c] != 14 { status_code = 2 }
    if [[a + b] * [c - 1]] != 15 { status_code = 3 }
    if [a < b and b < c] == false { status_code = 4 }
    wide : Int64 = [2147483648]
    if wide != 2147483648 { status_code = 5 }
    index : UIntNative = 2
    array : [3]Int32 = (10, 20, 30)
    if array[[index - 1]] != 20 { status_code = 6 }
    if [array][index] != 30 { status_code = 7 }
    [a] = 1
    pointer ::= $&[a]
    pointer& = 2
    [array[index]] = 40
    point :: Point = Point(.x = 1)
    [point.x] = 7
    if a != 2 or array[index] != 40 or [point].x != 7 { status_code = 8 }
    copied ::= [identity]#(.t: Int32)(.value = [a + b])
    if copied != 5 { status_code = 9 }
    extent : Array#(.n = [2 + 3] * 2, .t: UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    view ::= array_view_ro(.array = &extent)
    if length(.self = &view).count != 10 { status_code = 10 }
}
