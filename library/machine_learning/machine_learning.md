### Machine learning

Tiene que poder trackear el grafo de operaciones y diferenciar.

Inspirarse en JAX, pytorch

```
Layer :: Abstract = [
	forward(_, Tracked<NDVector>) -> Tracked<NDVector>
]

DenseLayer :: Type = struct [
	._weights: Parameter<NDVector>
	._biases: Parameter<NDVector>
]

Layer canbe DenseLayer

init(#t::==DenseLayer, input_size: Int, output_size: Int) ::= DenseLayer {
	weights = NDVector|init([input_size, output_size])
	biases  = NDVector|init([output_size])
	return DenseLayer(weights, bias)
}

forward(layer : DenseLayer, input :: Tracked<NDVector>) ::= Tracked<NDVector> {
	return input|dot(layer._weights)|add(layer._biases)
}
```

Use:
```
MyModel :: Type = struct [
	._layers: List<Layer> = [
		DenseLayer|init(3, 4)
		DenseLayer|init(4, 2)
	]
]

forward(#t::==MyModel, input :: Tracked<NDVector>) ::= Tracked<NDVector> {
	for layer in model._layers {
		input = layer|forward(input)
	}
	return input
}

loss(#t::==MyModel, input :: Tracked<NDVector>, target :: Tracked<NDVector>) ::= Tracked<Float> {
	prediction = model|forward(input)
	return mse(prediction, target)
}

model :: MyModel = MyModel()

input :: Tracked<NDVector> = NDVector|init([3])
target :: Tracked<NDVector> = NDVector|init([2])

loss = model|loss(input, target)

deltas ::= loss|backward()
deltas.apply_gradients(0.01)
```

O algo así.

