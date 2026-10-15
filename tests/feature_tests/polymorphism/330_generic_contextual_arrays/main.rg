byte#(.T: Type)(.marker: T) -> (.result: UInt8) := {
    bytes :: [1]UInt8 = (0)
    matrix: [2][2]UInt8 = ((1, 2), (3, 255))
    if matrix[0][1] != 2 or matrix[1][1] != 255 { abort }
    record: (.bytes: [2]UInt8) = (.bytes = (1, 255))
    if record.bytes[1] != 255 { abort }
    floats: [1]Float64 = (0.5)
    if floats[0] != 0.5 { abort }
    bytes = (255)
    result = bytes[0]
}

main() -> () := {
    if byte#(Int32)(1).result != 255 { abort }
    if byte#(Bool)(true).result != 255 { abort }
}
