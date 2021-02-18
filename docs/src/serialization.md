## Saving results

In just four lines of code, we can setup serialization of collections of AnalyzeRegistry's `Package` object to Apache arrow tables:

```@repl 1
using Arrow, AnalyzeRegistry
Arrow.ArrowTypes.registertype!(AnalyzeRegistry.Package, AnalyzeRegistry.Package)
save(path, packages) = Arrow.write(path, (; packages))
load(path) = copy(Arrow.Table(path).packages)
```

Then we can do e.g.

```@repl 1
results = analyze_from_registry(find_packages("DataFrames", "Flux"));
save("packages.arrow", results)
roundtripped_results = load("packages.arrow")
rm("packages.arrow") # hide
```

Note that even if future versions of AnalyzeRegistry change the layout of `Package`'s and you forget the version used to serialize the results, you can use the same `load` function *without* calling `registertype!` in the Julia session in order to deserialize the results back as `NamedTuple`'s (instead of as `Package`s), providing some amount of robustness.
