# These functions take in user-friendly strings / URLs / modules,
# and call `analyze` or `analyze_packages` with `PkgSource`'s.
"""
    analyze(name_or_dir_or_url::AbstractString; repo = "", reachable=true, subdir="", registry=general_registry(), auth::GitHub.Authorization=github_auth(), version::AbstractVersion=:dev)

Analyze the package pointed to by the mandatory argument and return a summary of
its properties.

If `name_or_dir_or_url` is a valid Julia identifier, it is assumed to be the name of a
package available in `registry`.  The function then uses [`find_package`](@ref)
to find its entry in the registry and analyze its content.

If `name_or_dir_or_url` is a filesystem path, analyze the package whose source code is
located at `name_or_dir_or_url`. Optionally `repo` and `reachable` a boolean indicating
whether or not the package is reachable online, since these can't be inferred
from the source code.  The `subdir` keyword arguments indicates the subdirectory
of `dir` under which the Julia package can be found.

Otherwise, `name_or_dir_or_url` is assumed to be a URL. The repository is cloned to a temporary directory
and analyzed.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected.  Only the number
of contributors will be shown in the summary.  See
[`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.

Pass the keyword argument `version` to confgiure which version of the code is analyzed. Options:

* `:dev` to use the latest code in the repository
* `:stable` to use the latest released version of the code, or
* pass a `VersionNumber` to analyze a particular version of the package.

If `version !== :dev`, only the code associated to that version of the package will be downloaded.
That means for packages in subdirectories, top-level information (like CI scripts) may be unavailable.

## Example

You can analyze a package just by its name, whether you have it installed
locally or not:

```julia
julia> analyze("Pluto"; version=v"0.18.0")
Package Pluto:
  * repo: https://github.com/fonsp/Pluto.jl.git
  * uuid: c3e4b0f8-55cb-11ea-2926-15256bba5781
  * version: 0.18.0
  * is reachable: true
  * tree hash: db1306745717d127037c5697436b04cfb9d7b3dd
  * Julia code in `src`: 8337 lines
  * Julia code in `test`: 5448 lines (39.5% of `test` + `src`)
  * documention in `docs`: 0 lines (0.0% of `docs` + `src`)
  * documention in README: 118 lines
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * has license(s) in Project.toml: MIT
    * OSI approved: true
  * has `docs/make.jl`: false
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions

```
"""
function analyze(name_or_dir_or_url::AbstractString; repo="", reachable=true, subdir="", registries=reachable_registries(), auth::GitHub.Authorization=github_auth(), sleep=0, version=nothing)
    if Base.isidentifier(name_or_dir_or_url)
        # The argument looks like a package name rather than a directory: find
        # the package in `registry` and analyze it
        release = Release(find_package(name_or_dir_or_url; registries), version)
        return analyze(release; auth, sleep)
    elseif isdir(name_or_dir_or_url)
        # Local directory
        if version !== nothing
            error("")
        end
        return analyze(Dev(; path=name_or_dir_or_url); repo, reachable, subdir, auth, sleep)
    else
        # Remote URL
        if version !== nothing
            error("Not supported")
        end
        return analyze(Dev(; repo_url=name_or_dir_or_url); subdir, auth, sleep)
    end
end


"""
    analyze(m::Module; kwargs...) -> Package

If you want to analyze a package which is already loaded in the current session,
you can simply call `analyze`, which uses `pkgdir` to determine its source code:

```julia
julia> using DataFrames

julia> analyze(DataFrames)
Package DataFrames:
  * repo: 
  * uuid: a93c6f00-e57d-5684-b7b6-d8193f3e46c0
  * version: 0.0.0
  * is reachable: true
  * tree hash: db2a9cb664fcea7836da4b414c3278d71dd602d2
  * Julia code in `src`: 15628 lines
  * Julia code in `test`: 21089 lines (57.4% of `test` + `src`)
  * documention in `docs`: 6270 lines (28.6% of `docs` + `src`)
  * documention in README: 21 lines
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
```
"""
analyze(m::Module; kwargs...) = analyze_path(Dev(; path=pkgdir(m)); kwargs...)


"""
    analyze_manifest([path_to_manifest]; registries=reachable_registries(),
                     auth=github_auth(), sleep=0)

Convienence function to run [`find_packages_in_manifest`](@ref) then [`analyze`](@ref) on the results. Positional argument `path_to_manifest` defaults to `joinpath(dirname(Base.active_project()), "Manifest.toml")`.
"""
function analyze_manifest(args...; registries=reachable_registries(),
                          auth=github_auth(), sleep=0)
    pkgs = find_packages_in_manifest(args...; registries)
    return analyze_packages(pkgs; auth, sleep)
end
