-- Consider whether the capability belongs here.

Clock : Type = ()

once Clock init() -> (.result: Clock) := {
    result = ()

}
-- getCurrentTime :: IO UTCTime
-- Gets the current time in UTC.
-- getZonedTime :: IO ZonedTime
-- Gets the current time in the local time zone.
-- threadDelay :: Int → IO ()
-- Suspends the current thread for N microseconds.

-------


-- Clock     : Type = ()
-- TimeUnit  : Type = (..ns, ..us, ..ms, ..s, ..min, ..h, ..d, ..w, ..mo, ..y)
-- Duration  : Type = NumberWithUnit#(.t: Int, .unit: TimeUnit) -- Perhaps nanoseconds are enough.
-- TimeStamp : Type = NumberWithUnit#(.t: Int, .unit: TimeUnit) -- Perhaps nanoseconds are enough.
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
