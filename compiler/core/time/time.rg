-- Pensar si la capability tiene que ir aquí o no

Clock : Type = ()
-- getCurrentTime :: IO UTCTime
-- Obtiene la hora actual en UTC.
-- getZonedTime :: IO ZonedTime
-- Obtiene la hora actual con zona horaria local.
-- threadDelay :: Int → IO ()
-- Suspende el hilo actual N microsegundos

-------


-- Clock     : Type = ()
-- TimeUnit  : Type = (..ns, ..us, ..ms, ..s, ..min, ..h, ..d, ..w, ..mo, ..y)
-- Duration  : Type = NumberWithUnit#(.t: Int, .unit: TimeUnit) -- Igual mejor ns y ya.
-- TimeStamp : Type = NumberWithUnit#(.t: Int, .unit: TimeUnit) -- Igual mejor ns y ya.
-- 
-- Date : Type = (
-- 	.year: Int
-- 	.month: Int
-- 	.day: Int
-- )
-- 
-- Time : Type = (
-- 	.hour: Int
-- 	.minute: Int
-- 	.second: Int
-- )
-- 
-- DateTime : Type = (
-- 	.date: Date
-- 	.time: Time
-- )
