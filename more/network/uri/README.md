# URI references

Import `network/uri` to parse and recompose encoded URI references. The module
uses RFC 3986 generic syntax, independently of networking or HTTP. `parse`
returns an `Errable<UriView, invalid_input>` containing borrowed `scheme`,
`authority`, `path`, `query`, and `fragment` components. Optional components
preserve absent versus present-empty values. Source storage must outlive them.

Both absolute and relative references are accepted. Parsing validates ASCII
component grammar, percent triplets, scheme syntax, authority delimiters,
bracketed IPv6/IPvFuture literals, and decimal port syntax. `authority_parts`
splits encoded userinfo, host, and port; IP-literal hosts retain their brackets.
Ports remain text: range and default-port rules depend on the scheme. This is
URI syntax validation, not DNS resolution, IDNA, or application URL policy.

`build(.value: UriView, .allocator)` returns an owning String or `invalid_input` /
`out_of_memory`. Components are already encoded. It rejects delimiter injection,
a relative first segment containing a colon, an authority with a non-absolute
path, and a path starting with `//` without an authority. It preserves case,
percent-escape spelling, empty delimiters, and dot segments.

`encode_component(.text, .allocator)` percent-encodes every byte except ASCII
unreserved characters, using uppercase hex. UTF-8 bytes are encoded separately.
`decode_component` decodes valid triplets into an owning byte String and rejects
malformed escapes. It does not translate `+` to space or validate decoded UTF-8;
encoded NUL is an ordinary byte. Decode components only after separating their
structural delimiters. Query form encoding and base-URI resolution are separate
operations and are not provided by this module.

```rg
uri := import("network/uri")
main(.system: System) -> (.status_code: Int32 = 0) := {
    parsed ::= unwrap_or_abort(.value = uri.parse(.text = "https://example.com/a?x=1")).result
    text ::= unwrap_or_abort(.value = uri.build(.value = parsed,
        .allocator = system.page_allocator)).result
}
```

Reference: [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986).
