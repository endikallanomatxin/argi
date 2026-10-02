### Figures

A centralized figure type helps unify rendering.

```
Figure : Type = (
	.background_color: RGBAColor
	.layout: Layout
)

Layout :: Tree<LayoutElement>
```

Explore this further.



### Plotting

Like matplotlib, but cleaner and easier to use.

It should be possible to render to:

- Native interface (such as tkinter or raylib), with interactivity.
- Web, with interactivity.
- SVG
- PNG, JPG, etc.
- Terminal
	https://github.com/olavolav/uniplot
	https://en.wikipedia.org/wiki/Block_Elements
	http://gnuplot.info/docs/loc19448.html

The interface should support interactive plots.

A terminal plot could look like this:

```
my_series :: Series = [
    .x = [1, 2, 3, 4, 5],
    .y = [1, 4, 9, 16, 25],
    .label = "My series",
]

plot :: Plot = [
    .series = [my_series],
    .title = "My plot",
    .x_label = "X axis",
    .y_label = "Y axis",
]

plot|render(..terminal)|show

```

Additional options:

```
plot :: Plot = [
    ...
    .grid = true,
    .grid_config = [
        .color = "black",
        .style = "dotted",
    ]

    .legend = true,
    .legend_config = [
	.position = "top-right",
	.background_color = "white",
	.text_color = "black",
    ]

    .x_axis_config = [
	.show = true,
	.color = "black",
	.size = 1,
	.font = "Arial",
	.xlims = [0, 10],
    ]

    .y_axis_config = [
	.show = true,
	.color = "black",
	.size = 1,
	.font = "Arial",
	.ylims = [0, 30],
    ]

    .x_ticks_config = [
	.show = true,
	.color = "black",
	.size = 10,
	.font = "Arial",
    ]

    .y_ticks_config = [
	.show = true,
	.color = "black",
	.size = 10,
	.font = "Arial",
    ]

    .background_color = "white",
]
```
