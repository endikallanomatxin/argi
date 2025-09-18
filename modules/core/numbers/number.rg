Number : Abstract = (

    -- Have clear promotion rules
    promotion_type(.a: Self, .b: AnyOther) -> (.t: Type<:Other)
    promotion_type(.a: AnyOther, .b: Self) -> (.t: Type<:Other)
    -- TODO: Pensar esto bien

)
