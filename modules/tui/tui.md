### UI

- UI

log:
- print debe permitir indentación
- warnings
- texto con estilo

#### TUI

 Text & Messaging
Default/Body:
The standard style for general text.

Title/Heading & Subtitle:
Distinct styles for headers, titles, and section subtitles.

Link/Interactive Text:
Styling for text that acts as a link or triggers an action.

Emphasis:
For text that needs to stand out (could include bold, underline, or color accents).

2. Feedback & Alerts
Error:
For error messages or critical alerts (often using red or a similarly strong color).

Warning:
For cautionary messages (typically yellow or orange).

Info:
For informational messages (often blue or neutral tones).

Success:
For confirmations or positive outcomes (commonly green).

3. Interactive Element States
For widgets like buttons, inputs, and menus, consider defining different states:

Normal:
The default appearance of an interactive element.

Focused/Active:
Styling for when an element is currently selected or in focus.

Pressed/Active Interaction:
A temporary state when a button is pressed or an element is actively being used.

Disabled:
For elements that are inactive or unavailable.

Hovered (if applicable):
For mouse-over or similar interactions, if your TUI supports them.

4. Structural & Decorative Elements
Borders & Frames:
Styles for delineating panels, windows, or sections.

Backgrounds & Panels:
Different background styles for various areas of the interface (e.g., sidebars, main content areas).

Accents/Highlights:
For drawing attention to specific UI parts (like a selected list item or highlighted text).

Additional Considerations
Widget-Specific Styles:
If your TUI library provides common widgets (like checkboxes, radio buttons, progress bars, etc.), it can be helpful to have default styles for these as well, including their various interactive states.

Attributes Beyond Color:
Besides color, think about text attributes (bold, underline, italic) as part of your style definitions. This allows for richer customization without relying solely on color differences.

Customization & Extensibility:
Provide a mechanism for users to override or extend these defaults. This might include a configuration file or API for changing style definitions easily.

b. Unicode Box-Drawing Characters
Using Unicode offers a more polished look with smoother lines and rounded corners:

css
Copiar
╭──────────────╮
│ Panel Title  │
├──────────────┤
│ Content      │
│ More content │
╰──────────────╯
Usage idea:
Allow your TUI to detect terminal capabilities and switch to Unicode borders when available. You can even offer multiple styles (e.g., rounded corners vs. square corners).

Titles:
```
╭────── My Panel ──────╮
│  Content goes here   │
│  More content        │
╰──────────────────────╯
```

Python rich hace  con argumentos. Algo así quedaría:

```
my_panel :: Panel(
    [Pane("content")],
    title = "my_tytle",
    border-color = "green"
    border-style = "squared" -- vs. rounded
)

my_panel|print
```

Rust TUI-RS y Go Tview usan algo más parecido a un builder pattern.
Igual es simplemente porque no tienen default arguments.


Pensar también en como hacer una table.
Syntax highlighting.
Logging
Progress bars
Trees
Markdown rendering.

Modos: podría haber como: stagedTUI, o singlepageTUI

TRACEBACKS de errores.
Desarrollar la librería para que esto se haga bien bonito. Y así ya tenemos la librería en sí. Intentar poner todo lo posible en la librería de TUI.
(tracebacks como se ven en python's rich, están muy bien, que te imprima las variables locales disponibles está super bien.)

Echarle un ojo a textual, para python, lleva el concepto de TUI un poco más allá

>[!QUOTE]  Primeagen
>I love rust for cli tools.


