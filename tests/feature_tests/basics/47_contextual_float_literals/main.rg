Values : Type = (.wide: Float64, .narrow: Float32)
identity(.value: Float64) -> (.result: Float64) := { result = value }
identity_generic#(.t: Type)(.value: t) -> (.result: t) := { result = value }
main() -> (.status_code: Int32 = 0) := {
    wide :: Float64 = 3.5
    narrow :: Float32 = 3.5
    values : Values = (.wide = 3.5, .narrow = 3.5)
    array : [2]Float64 = (3.5, 7.0)
    constructed := Values(.wide = 3.5, .narrow = 3.5)
    mutable :: Float64 = 1.0
    mutable = 3.5
    pointer := $&mutable
    pointer& = 7.0
    result := identity(3.5)
    generic := identity_generic#(.t: Float64)(3.5)
    if wide != values.wide or narrow != values.narrow { status_code = 1 }
    if result != wide or generic != wide or array[0] != wide { status_code = 2 }
    if constructed.wide != wide or mutable != array[1] { status_code = 3 }
}
