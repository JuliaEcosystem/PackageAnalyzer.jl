## Saving results

PackageAnalyzer uses [Legolas.jl](https://github.com/beacon-biosignals/Legolas.jl) to define several schemas
to support serialization. These schemas may be updated in backwards-compatible ways in non-breaking releases,
by e.g. adding additional optional fields.

A table compliant with the `package-analyzer.package` schema may be serialized with
```julia
using Legolas
Legolas.write(io, table, PackageV1SchemaVersion())
```
and read back by
```julia
io = Legolas.read(io)
```

For example,
```@repl 1
using DataFrames, Legolas, PackageAnalyzer
results = analyze_packages(find_packages("DataFrames", "Flux"));
Legolas.write("packages.arrow", results, PackageV1SchemaVersion())
roundtripped_results = DataFrame(Arrow.Table("packages.arrow"))
rm("packages.arrow") # hide
```
