invalid#(.T: Type)(.marker: T) -> () := {
    bytes: [1]UInt8 = (0, 1)
}

main() -> () := { invalid#(Int32)(1) }
