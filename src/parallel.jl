"""
    analyze_packages(pkg_entries; auth::GitHub.Authorization=github_auth(), sleep=0, root=mktempdir()) -> Vector{Package}


Analyze all packages in the iterable `pkg_entries`, using threads, cloning them to `root`
if a directory with their `uuid` does not already exist.  Returns a
`Vector{Package}`.

Optionally, use pairs `(PkgEntry, $AbstractVersion)` to specify the version numbers, or pass a keyword argument `version`.
The version number may be a `VersionNumber`, or `:dev`, or `:stable`. When pairs are passed, the
keyword argument `version` will be ignored.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repositories is also collected, after waiting
for `sleep` seconds for each entry (useful to avoid getting rate-limited by
GitHub).  See [`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub
authentication.
"""
function analyze_packages(pkg_entries; auth::GitHub.Authorization=github_auth(), sleep=0, root=mktempdir())
    inputs = Channel{Tuple{Int,PkgSource}}(length(pkg_entries))
    for (i, r) in enumerate(pkg_entries)
        put!(inputs, (i, r))
    end
    close(inputs)
    outputs = Channel{Tuple{Int,Package}}(length(pkg_entries))
    Threads.foreach(inputs) do (i, pkg)
        put!(outputs, (i, analyze(pkg; auth, sleep, root)))
    end
    close(outputs)
    return last.(sort!(collect(outputs); by=first))
end
