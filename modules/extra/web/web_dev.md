# Web app development

>[!TIP] Inspire on:
> React
> Good rust crates:
>	- Leptose - frontend+fullsack
>	- Actix - Http server
>	- Yew - frontend
>	- Dioxus - frontend
> Elm
> Fresh2
> grecha.js


## Frontend

Compile to WASM or JS.

### Functional way of declaring templates.

Tiene que ser un poco functional, más que imperative.

See go templ

Aunque realmente lo único que necesito es simplemente una función.
Yo creo que es la mejor forma de hacer templating.

#### Web UI Component

```
WebComponent :: Type = [
	.html : List<HTML>
	.css  : List<CSS>
	.js   : List<JS>
]

HTML :: Type = String
CSS  :: Type = String
JS   :: Type = String

```

No se yo si es lo mejor, por que CSS y JS es mejor que se manden como archivos estáticos que se aprovechan de poder cachearse.

Igual podríamos hacer algo rollo GenerateAndCollectStatic. O algo así. Pero para eso habría que tener todos los componentes registrados en alguna variable.


```
my_component : WebComponent = [

	.my_var : Int

	.html := htmltemplate"""
		<div>
			<p>Count: {my_var}</p>
		</div>
	"""

	.css := csstemplate"""
		<style>
			p {
				color: red;
			}
		</style>
	"""

	.js := jstemplate"""
		<script>
			let count = 0;
			setInterval(() => {
				count++;
				document.querySelector('p').innerText = 'Count: ' + count;
			}, 1000);
		</script>
	"""
]
```


Igual es mejor una sintaxis rollo:

```
my_component : WebComponent = [
	.content := [
		.div := [
			.p := [
				.text := "Count: {my_var}"
			]
		]
	]

	.state := [
		.my_var := 0
	]
```

O igual un estilo más funcional:

```
my_component(my_var) := [
	Component(
		.content := [
			.div := [
				.p := [
					.text := "Count: {my_var}"
				]
			]
		]
	)
)
```


O algo más como elm:

```
Element : Interface = [
	view : (_) -> HTML
	-- update : (_) -- Igual mejor no es parte de la interfaz, sino algo opcional.
]

MyElement : Type = [
	.some_state : int
]

view(e: &MyElement) := Div(
	[
		P(
			[
				Text("Count: {e.some_state}", onclick=update(e, e.some_state + 1))
				-- O igual update no debería verse ahí, sino solo los argumentos?
				-- Darle una vuelta.
			]
		)
	]
)

update(e: &MyElement, new_state: int) := {
	e.some_state = new_state
}
```

Yo creo que ese es el camino.


Elm Architecture:

- Wait for user input.
- Send a message to update
- Produce a new Model
- Call view to get new HTML
- Show the new HTML on screen
- Repeat!

Luego todo esto se compila a js.

```
LoginForm : Type = [
	.email : String
	.password : String
]

init(t==LoginForm) := {
	return LoginForm[
		.email = ""
		.password = ""
	]
}

view(e: &LoginForm) := [
	Div(
		[
			Input(type="email", value=e.email, oninput=update_email(e, e.email))
			Input(type="password", value=e.password, oninput=update_password(e, e.password))
			Button("Submit", onclick=submit(e))
		]
	)
]

update_email(e: &LoginForm, new_email: String) := {
	e.email = new_email
}

update_password(e: &LoginForm, new_password: String) := {
	e.password = new_password
}

submit(e: &LoginForm) := {
	-- Pensar en como conectarlo con el frontend.
}
```



#### Autoupdate

Reactivity

```
my_state := AutoUpdateState(&my_var)

my_thing := """html
	<p>Count: {my_state}</p>
	"""
```

En lugar de poner la variable, pone el js necesario para que haga listen a cambios, server side events.


#### Page transition

Pensar en como hacerlo.


#### Multiplatform native

Que se pueda convertir en aplicaciones nativas. Como dioxus.


## Backend

### Assets

```
Asset :: Type = [...]

my_image : Asset = [...]
```

Cuando se hace el frontend, se referencian.


