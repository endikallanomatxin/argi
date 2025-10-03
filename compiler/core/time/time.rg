-- Pensar si la capability tiene que ir aquí o no

Clock : Type = ()
-- getCurrentTime :: IO UTCTime
-- Obtiene la hora actual en UTC.
-- getZonedTime :: IO ZonedTime
-- Obtiene la hora actual con zona horaria local.
-- threadDelay :: Int → IO ()
-- Suspende el hilo actual N microsegundos

-------


-- Clock     : type = struct []
-- TimeUnit  : type = [..ns, ..us, ..ms, ..s, ..min, ..h, ..d, ..w, ..mo, ..y]
-- Duration  : type = NumberWithUnit<Int, TimeUnit> -- Igual mejor ns y ya.
-- TimeStamp : type = NumberWithUnit<Int, TimeUnit> -- Igual mejor ns y ya.
-- 
-- Date :: Type = struct [
-- 	.year: Int
-- 	.month: Int
-- 	.day: Int
-- ]
-- 
-- Time :: Type = struct [
-- 	.hour: Int
-- 	.minute: Int
-- 	.second: Int
-- ]
-- 
-- DateTime :: Type = struct [
-- 	.date: Date
-- 	.time: Time
-- ]
