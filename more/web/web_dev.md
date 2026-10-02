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

It should be somewhat functional rather than imperative.

See go templ

Though all I really need is a function.
I think this is the best way to do templating.

#### Web UI Component

```
WebComponent : Type = (
	.html : List#(.t: HTML)
	.css  : List#(.t: CSS)
	.js   : List#(.t: JS)
)

HTML :: Type = String
CSS  :: Type = String
JS   :: Type = String

```

I am not sure this is best, because CSS and JS are better served as static files that can be cached.

We could provide something like `GenerateAndCollectStatic`. That would require registering all components in a shared variable.


```
my_component : WebComponent = (

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
)
```


Perhaps a syntax like this would be better:

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

Or perhaps a more functional style:

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


Or something closer to Elm:

```
Element : Interface = [
	view : (_) -> HTML
	-- update : (_) -- Perhaps this should be optional rather than part of the interface.
]

MyElement : Type = [
	.some_state : Int
]

view(e: &MyElement) := Div(
	[
		P(
			[
				Text("Count: {e.some_state}", onclick=update(e, e.some_state + 1))
				-- Perhaps update should not appear here, only its arguments?
				-- Reconsider this.
			]
		)
	]
)

update(e: &MyElement, new_state: Int) := {
	e.some_state = new_state
}
```

I think that is the way to go.


Elm Architecture:

- Wait for user input.
- Send a message to update
- Produce a new Model
- Call view to get new HTML
- Show the new HTML on screen
- Repeat!

All of this is then compiled to JS.

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
	-- Consider how to connect this to the frontend.
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

Instead of inserting the variable, generate the JS needed to listen for changes, such as server-sent events.


#### Page transition

Consider how to implement this.


#### Multiplatform native

It should be possible to turn these into native applications, as with Dioxus.


## Backend

### Assets

```
Asset :: Type = [...]

my_image : Asset = [...]
```

These are referenced when building the frontend.
