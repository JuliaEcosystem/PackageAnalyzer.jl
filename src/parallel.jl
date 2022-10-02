"""
    analyze_packages(pkg_entries; auth::GitHub.Authorization=github_auth(), sleep=0, root=mktempdir()) -> Vector{Package}


Analyze all packages in the iterable `pkg_entries`, using threads, storing their code in `root`
if it needs to be downloaded.  Returns a `Vector{Package}`.

Each element of `pkg_entries` should be a valid input to [`analyze`](@ref).

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
