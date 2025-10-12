RandomNumberGenerator : Type = ()

-- randomRIO :: Random a ⇒ (a, a) → IO a
-- Genera un valor aleatorio en el rango inclusivo dado, usando la generación global.
-- getStdRandom :: (StdGen → (a, StdGen)) → IO a
-- Permite usar funciones que trabajan con el generador de manera puramente funcional, actualizando la semilla interna.
-- newStdGen :: IO StdGen
-- Separa el generador global en dos: uno nuevo para el hilo, y devuelve el que queda para uso puro.
