[![Build Status](https://github.com/giordano/AnalyzeRegistry.jl/workflows/CI/badge.svg)](https://github.com/giordano/AnalyzeRegistry.jl/actions?query=workflow%3ACI)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://giordano.github.io/AnalyzeRegistry.jl/dev/)

# AnalyzeRegistry

Package to analyze the prevalence of documentation, testing and continuous
integration in Julia packages in a given registry.

## Installation

The package works on Julia v1.6 and following versions.

To install the package, in Julia's REPL, press `]` to enter the Pkg mode and run
the command

```
add https://github.com/giordano/AnalyzeRegistry.jl
```

Alternatively, you can run

```julia
using Pkg
Pkg.add("https://github.com/giordano/AnalyzeRegistry.jl")
```

## Quick example

```julia
julia> using AnalyzeRegistry

julia> analyze("Flux")
Package Flux:
  * repo: https://github.com/FluxML/Flux.jl.git
  * uuid: 587475ba-b771-5e3f-ad9e-33799f191a9c
  * is reachable: true
  * lines of Julia code in `src`: 5074
  * lines of Julia code in `test`: 2167
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * number of contributors: 151
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
    * Buildkite

```

See the [docs](https://giordano.github.io/AnalyzeRegistry.jl/dev/) for more!

## License

The `AnalyzeRegistry.jl` package is licensed under the MIT "Expat" License.  The
original author is Mosè Giordano.
