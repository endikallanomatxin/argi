accept_c_text := (.text: &CChar) -> () {}

main := () -> () {
    text: StringView = "retained text"
    accept_c_text(.text = text)
}
