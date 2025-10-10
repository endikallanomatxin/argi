Objetivo: poner un deinit justo después del último uso.
En realidad con que estuvieran después, en cualquier momento ya valdría.
Entonces la implementación de poner todos los deinits al final del programa podría valer.
Ahora bien, podemos hacer un programa que vaya del final hacia arriba checkeando el último uso.
Y vaya subiendo los deinits tanto como se pueda.

