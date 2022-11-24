## Saving results

Since a `Vector{Package}` is a Tables.jl-compatible row table, one does not need to do anything special
to save the results as a table. For example,

```@repl 1
using DataFrames, Arrow, PackageAnalyzer
results = analyze_packages(find_packages("DataFrames", "Flux"));
Arrow.write("packages.arrow", results)
roundtripped_results = DataFrame(Arrow.Table("packages.arrow"))
rm("packages.arrow") # hide
```
