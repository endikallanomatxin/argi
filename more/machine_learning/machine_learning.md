### Machine learning

Tiene que poder trackear el grafo de operaciones y diferenciar.

Inspirarse en JAX, pytorch

```
Layer : Abstract = (
	forward(.layer: Self, .input: Tracked#(.t: NDVector)) -> (.output: Tracked#(.t: NDVector))
)

DenseLayer : Type = (
	._weights: Parameter#(.t: NDVector)
	._biases: Parameter#(.t: NDVector)
)

DenseLayer implements Layer

init(.p: $&DenseLayer, .input_size: Int, .output_size: Int) -> () := {
	weights = NDVector((input_size, output_size))
	biases  = NDVector((output_size))
	p& = (
		._weights = weights,
		._biases = biases,
	)
}

forward(.layer: DenseLayer, .input: Tracked#(.t: NDVector)) -> (.output: Tracked#(.t: NDVector)) := {
	output = input|dot(layer._weights)|add(layer._biases)
}
```

Use:
```
MyModel : Type = (
	._layers: List#(.t: Layer) = (
		DenseLayer(3, 4)
		DenseLayer(4, 2)
	)
)

forward(.model: MyModel, .input: Tracked#(.t: NDVector)) -> (.output: Tracked#(.t: NDVector)) := {
	for layer in model._layers {
		input = layer|forward(input)
	}
	output = input
}

loss(.model: MyModel, .input: Tracked#(.t: NDVector), .target: Tracked#(.t: NDVector)) -> (.value: Tracked#(.t: Float)) := {
	prediction = model|forward(input)
	value = mse(prediction, target)
}

model :: MyModel = MyModel()

input :: Tracked#(.t: NDVector) = NDVector((3))
target :: Tracked#(.t: NDVector) = NDVector((2))

loss = model|loss(input, target)

deltas ::= loss|backward()
deltas.apply_gradients(0.01)
```

O algo así.
