#### Testing

```
test "If statement" {
	a: bool = true
	x: u16 = 0

	if a {
		x += 1
	} else {
		x += 2
	}

	assert(x == 1)
}
```

(from zig)
