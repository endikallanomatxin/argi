main () -> (.status_code: Int32) := {
    puts(.string="Hello world!")

    size :: UIntNative = 14
    p : $&Char = malloc(.size=size)
    p& = '0'
    puts(.string=p)
    free(.pointer=p)

    putchar(.character=10)
    status_code = 0
}
