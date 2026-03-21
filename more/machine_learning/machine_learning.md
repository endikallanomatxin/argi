### Machine learning

Tiene que poder trackear el grafo de operaciones y diferenciar.

Inspirarse en JAX, pytorch

```
Layer : Abstract = (
	forward(.layer: Self, .input: Tracked<NDVector>) -> (.output: Tracked<NDVector>)
)

DenseLayer : Type = (
	._weights: Parameter<NDVector>
	._biases: Parameter<NDVector>
)

DenseLayer implements Layer

init(.p: $&DenseLayer, .input_size: Int, .output_size: Int) -> () := {
	weights = NDVector|init([input_size, output_size])
	biases  = NDVector|init([output_size])
	p& = (
		._weights = weights,
		._biases = biases,
	)
}

forward(.layer: DenseLayer, .input: Tracked<NDVector>) -> (.output: Tracked<NDVector>) := {
	output = input|dot(layer._weights)|add(layer._biases)
}
```

Use:
```
MyModel : Type = (
	._layers: List<Layer> = [
		DenseLayer|init(3, 4)
		DenseLayer|init(4, 2)
	]
)

forward(.model: MyModel, .input: Tracked<NDVector>) -> (.output: Tracked<NDVector>) := {
	for layer in model._layers {
		input = layer|forward(input)
	}
	output = input
}

loss(.model: MyModel, .input: Tracked<NDVector>, .target: Tracked<NDVector>) -> (.value: Tracked<Float>) := {
	prediction = model|forward(input)
	value = mse(prediction, target)
}

model :: MyModel = MyModel()

input :: Tracked<NDVector> = NDVector|init([3])
target :: Tracked<NDVector> = NDVector|init([2])

loss = model|loss(input, target)

deltas ::= loss|backward()
deltas.apply_gradients(0.01)
```

O algo así.
