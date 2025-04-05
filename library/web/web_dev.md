# Web app development

>[!TIP] Inspire on:
> React
> Good rust crates:
>	- Leptose - frontend+fullsack
>	- Actix - Http server
> Elm
> grecha.js

Compile to WASM or JS.

## Functional way of declaring templates.

Tiene que ser un poco functional, más que imperative.

See go templ

Aunque realmente lo único que necesito es simplemente una función.
Yo creo que es la mejor forma de hacer templating.

### Web UI Component

```
WebComponent :: Type = struct {
	html : List<HTML>
	css  : List<CSS>
	js   : List<JS>
}

HTML :: Type = String
CSS  :: Type = String
JS   :: Type = String

```

No se yo si es lo mejor, por que CSS y JS es mejor que se manden como archivos estáticos que se aprovechan de poder cachearse.

Igual podríamos hacer algo rollo GenerateAndCollectStatic. O algo así. Pero para eso habría que tener todos los componentes registrados en alguna variable.



## Autoupdate

Reactivity

```
my_state := AutoUpdateState(&my_var)

my_thing := """html
	<p>Count: {my_state}</p>
	"""
```

En lugar de poner la variable, pone el js necesario para que haga listen a cambios, server side events.



