Deinit#(.T: Type): Contract = (
    .deinit : (.self: $&T) -> () where consumes(self)
)
