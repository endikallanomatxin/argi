String :: Abstract = [
	-- For chars (most sensible default)
	operator get[]
	operator set[]
	length(_) :: Int

	-- For bytes if needed
	byte_get()
	byte_set()
	byte_lentgh()
]

String canbe StaticString
String canbe DynamicString
String defaultsto DynamicString


StaticString :: Abstract = []

StaticString canbe StackArrayString
StaticString canbe StaticArrayString

StaticString defaultsto StaticArrayString


DynamicString :: Abstract = [
    push()
    push_str()
    pop()
    ...
]

DynamicString canbe CopyingDynamicArrayString
DynamicString canbe SegmentedDynamicArrayString

DynamicString defaultsto CopyingDynamicArrayString



StringView :: Type = [
    ---
    String view is a read only pointer to a section of a string.
    ---
    ._original   :: String
    ._from_index :  Index
    ._to_index   :  Index
]


