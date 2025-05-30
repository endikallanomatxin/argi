Clock     : type = struct []
TimeUnit  : type = [..ns, ..us, ..ms, ..s, ..min, ..h, ..d, ..w, ..mo, ..y]
Duration  : type = NumberWithUnit<Int, TimeUnit> -- Igual mejor ns y ya.
TimeStamp : type = NumberWithUnit<Int, TimeUnit> -- Igual mejor ns y ya.

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
