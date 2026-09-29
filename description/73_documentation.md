# Documentation comments

`--` introduces a line comment. Documentation comments could be collected
from source declarations and rendered by language tooling.

> [!IDEA]
> A distinct delimiter such as `---` could mark documentation comments:
>
> ```rg
> --- Explain the declaration below.
> Widget : Type = ()
> ```
>
> Multiline documentation might use paired `---` delimiters. This overlaps
> with a proposed multiline ordinary comment form in
> [Syntax overview](00_syntax_overview.md); choose delimiters for both
> together. Markdown inside documentation comments is also an option.

> [!IDEA]
> `argi doc` could build documentation from these comments, and
> `argi serve-doc` could preview it locally.
