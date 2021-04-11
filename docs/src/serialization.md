## Saving results

In just four lines of code, we can setup serialization of collections of PackageAnalyzer's `Package` object to Apache arrow tables:

```@repl 1
using PackageAnalyzer
using Arrow # v1.3+
ArrowTypes.arrowname(::Type{PackageAnalyzer.Package}) = Symbol("JuliaLang.PackageAnalyzer.Package")
ArrowTypes.JuliaType(::Val{Symbol("JuliaLang.PackageAnalyzer.Package")}) = PackageAnalyzer.Package
save(path, packages) = Arrow.write(path, (; packages))
load(path) = copy(Arrow.Table(path).packages)
```

Then we can do e.g.

```@repl 1
results = analyze(find_packages("DataFrames", "Flux"));
save("packages.arrow", results)
roundtripped_results = load("packages.arrow")
rm("packages.arrow") # hide
```

Note that even if future versions of PackageAnalyzer change the layout of `Package`'s and you forget the version used to serialize the results, you can use the same `load` function *without* defining the `ArrowTypes.JuliaType` method in the Julia session in order to deserialize the results back as `NamedTuple`'s (instead of as `Package`s), providing some amount of robustness.
