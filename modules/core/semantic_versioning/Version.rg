Version : Type = [
    .major : UInt32
    .minor : UInt32
    .patch : UInt32
]

-- Comparación

operator == (v1: Version, v2: Version) : Bool {
	return v1.major == v2.major and v1.minor == v2.minor and v1.patch == v2.patch
}

operator != (v1: Version, v2: Version) : Bool {
	return not(v1 == v2)
}

operator < (v1: Version, v2: Version) : Bool {
    ...
}
