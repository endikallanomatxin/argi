Follow Zig's approach, which works very well.

Perhaps this could work as follows:

```
a = 1  -- This is an inline comment.

--
This is a multiline comment.
--

b = 2  --- This is an inline documentation comment.

---
This is a multiline documentation comment.
---
```

And collect the `---` documentation comments when building documentation.

```bash
argi doc
```

```bash
argi serve-doc
```
