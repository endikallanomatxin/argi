# SQL query abstraction

[!IDEA] Exploratory design sketch; this is not an executable module.

```text
SQLDB : Type = [
	-- An SQL Database Descriptor
]

execute(db: SQLDB, ...) := {
	...
}


---
I want that that type to be an abstraction that allows to interact with an sql database without having to directly write sql.
Something more similar to Google's pipe syntax: https://cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax

Example:

my_db : SQLDB = SQLDB(...)

result = my_db
         | from(&_, "produce")
	 | where(&_, "item == banana")  -- These expressions could be integrated too.
	 | group_by(&_, "item")
	 | order_by(&_, "item", ..desc)
---
```
