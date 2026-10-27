Product #(.Left: Type, .Right: Type ): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row := (.value: Int32)
Column := (.value: Int32)
Row satisfies Product < Int32 >
main := () -> () {}
