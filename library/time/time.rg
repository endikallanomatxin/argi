Date :: Type = struct [
	.year: Int
	.month: Int
	.day: Int
]

Time :: Type = struct [
	.hour: Int
	.minute: Int
	.second: Int
]

DateTime :: Type = struct [
	.date: Date
	.time: Time
]
