### Figures

Tener un tipo figura centralizado viene bien para unificar todo el tema del renderizado.

```
Figure :: Type = struct [
	.background_color: RGBAColor
	.layout: Layout
]

Layout :: Tree<LayoutElement>
```

Explorar esto un poco



### Plotting

Like matplotlib, but cleaner and easier to use.

Tiene que poder renderizarse a:

- Interfaz nativa (algo como tkinter, raylib...)  (con capacidad interactiva)
- Web (con capacidad interactiva)
- SVG
- PNG, JPG, etc.
- Terminal
	https://github.com/olavolav/uniplot
	https://en.wikipedia.org/wiki/Block_Elements
	http://gnuplot.info/docs/loc19448.html

Es importante que la interfaz permita hacer gráficos interactivos.

Un plot en la terminal podría ser algo así:

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

Más cosas:

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


