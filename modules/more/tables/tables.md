### Tables

Pandas-like tables.

Declaring a table by rows:

```
my_table :: Table = [
    .header = ["Name", "Age", "Salary"],
    .rows = [
        ["Alice", 30, 70000],
        ["Bob", 25, 60000],
        ["Carol", 28, 65000],
    ]
]
```

Declaring a table by columns:

```
my_table :: Table = [
    "Name"  = ["Alice", "Bob", "Carol"]
    "Age"   = [     30,    25,      28]
    "Salary"= [  70000, 60000,   65000]
]
```


>[!TIP] Good rust crate
> Polars - Tables

```
data = read_csv_lazy("data.csv", has_header=True)
    | filter(col("age") > 21)
    | groupby("city")
    | agg([col("age").mean(), col("salary").sum()])
    | collect()
```

Plotting from tables:

```
data|print
```

```
shape: (4, 4)
┌────────────────┬────────────┬────────┬────────┐
│ name           ┆ birthdate  ┆ weight ┆ height │
│ ---            ┆ ---        ┆ ---    ┆ ---    │
│ str            ┆ date       ┆ f64    ┆ f64    │
╞════════════════╪════════════╪════════╪════════╡
│ Alice Archer   ┆ 1997-01-10 ┆ 57.9   ┆ 1.56   │
│ Ben Brown      ┆ 1985-02-15 ┆ 72.5   ┆ 1.77   │
│ Chloe Cooper   ┆ 1983-03-22 ┆ 53.6   ┆ 1.65   │
│ Daniel Donovan ┆ 1981-04-30 ┆ 83.1   ┆ 1.75   │
└────────────────┴────────────┴────────┴────────┘
```

Operations with columns:

```
data["height"] = data["height"] * 100
```

```
result = data
    | lazy
    | select([
        col("name")
        col("birthdate") | dt | year | alias("birth_year")
        (col("weight") / col("height").pow(2)) | alias("bmi")
    ])
    | collect()?
```

https://docs.pola.rs/user-guide/getting-started/#with_columns


