

"""
    analyze!(root, package::PkgEntry; auth::GitHub.Authorization=github_auth(), version::$AbstractVersion=:dev) -> Package

Analyze the package whose entry in the registry is in the `dir` directory,
cloning the package code to `joinpath(root, uuid)` where `uuid` is the UUID
of the package, if such a directory does not already exist.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected, after waiting for
`sleep` seconds.  Only the number of contributors will be shown in the summary.
See [`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.
"""
function analyze!(root, pkg::PkgEntry; auth::GitHub.Authorization=github_auth(), sleep=0, version::AbstractVersion=:dev)
    name = pkg.name
    uuid = pkg.uuid
    info = registry_info(pkg)
    repo = info.repo
    subdir = something(info.subdir, "")

    if version === :dev
        tree_sha = nothing
    else
        info = registry_info(pkg)
        if version === :stable
            version = maximum(keys(info.version_info))
            tree_sha = info.version_info[version].git_tree_sha1
        elseif version isa Symbol
            error("Unrecognized version $version. Must be `:dev`, `:stable`, or a `VersionNumber`.")
        else
            tree_sha = info.version_info[version].git_tree_sha1
        end
    end
    if tree_sha === nothing
        tree_hash = nothing
    else
        tree_hash = bytes2hex(tree_sha.bytes)
    end

    @debug "Analyzing version $version of $name"

    vs = tree_sha === nothing ? "dev" : Base.version_slug(uuid, tree_sha)
    dest = joinpath(root, name, vs)

    # Re-use logic.
    # We can never re-use dev, because maybe it got updated.
    # However if we have an actual tree hash there, we can use it.
    if isdir(dest)
        if version === :dev
            # Stale; cleanup
            rm(dest; recursive=true)
        else
            # We can re-use it! Assuming the contents are correct
            dest_tree_hash = bytes2hex(Pkg.GitTools.tree_hash(dest))
            if dest_tree_hash == tree_hash
                return analyze_path(dest; repo, subdir, auth, sleep, only_subdir=true, version)
            else
                @debug "Incorrect contents of $dest"
                rm(dest; recursive=true)
            end
        end
    end

    if version !== :dev
        # We have another chance to avoid the download: we can check inside the user's
        # package directory. Great for analyzing manifests where all versions
        # should be already installed!
        for d in Pkg.depots()
            path = joinpath(d, "packages", name, vs)
            isdir(path) || continue
            path_tree_hash = bytes2hex(Pkg.GitTools.tree_hash(path))
            if path_tree_hash == tree_hash
                @debug "Found installed path at $(path)! Using that"
                return analyze_path(path; repo, subdir, auth, sleep, only_subdir=true, version)
            end
        end
    end
    return analyze_path!(dest, repo; name, uuid, subdir, auth, sleep, tree_hash, version)
end



"""
    analyze_path(dir::AbstractString; repo = "", reachable=true, subdir="", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=v"0") -> Package

Analyze the package whose source code is located at the local path `dir`.  If
the package's repository is hosted on GitHub and `auth` is a non-anonymous
GitHub authentication, wait for `sleep` seconds before collecting the list of
its contributors.

`only_subdir` indicates that while the package's code does live in a subdirectory of the repo,
`dir` points only to that code and we do not have access to the top-level code. We still pass non-empty `subdir`
in this case, to record the fact that the package does indeed live in a subdirectory.

Pass `version` to store the associated version number. Since this call only has access to files on disk, it does not
know the associated version number in any registry.
"""
function analyze_path(dir::AbstractString; repo="", reachable=true, subdir="", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=v"0")
    # we will look for docs, tests, license, and count lines of code
    # in the `pkgdir`; we will look for CI in the `dir`.
    if only_subdir
        pkgdir = dir
    else
        pkgdir = joinpath(dir, subdir)
    end
    name, uuid, licenses_in_project = parse_project(pkgdir)
    docs = isfile(joinpath(pkgdir, "docs", "make.jl")) || isfile(joinpath(pkgdir, "doc", "make.jl"))
    runtests = isfile(joinpath(pkgdir, "test", "runtests.jl"))
    travis = isfile(joinpath(dir, ".travis.yml"))
    appveyor = isfile(joinpath(dir, "appveyor.yml"))
    cirrus = isfile(joinpath(dir, ".cirrus.yml"))
    circle = isfile(joinpath(dir, ".circleci", "config.yml"))
    drone = isfile(joinpath(dir, ".drone.yml"))
    azure_pipelines = isfile(joinpath(dir, "azure-pipelines.yml"))
    buildkite = isfile(joinpath(dir, ".buildkite", "pipeline.yml"))
    gitlab_pipeline = isfile(joinpath(dir, ".gitlab-ci.yml"))
    github_workflows = joinpath(dir, ".github", "workflows")
    if isdir(github_workflows)
        # Find all workflows
        files = readdir(github_workflows)
        # Exclude TagBot and CompatHelper
        filter(f -> lowercase(f) ∉ ("compathelper.yml", "tagbot.yml"), files)
        # Assume all other files are GitHub Actions for CI.  May not
        # _always_ be the case, but it's a good first-order approximation.
        github_actions = length(files) > 0
    else
        github_actions = false
    end
    # if `only_subdir` is true, and we are indeed in a subdirectory, we'll get the paths wrong here.
    # However, we'll find them w/ correct paths in the next check.
    license_files = only_subdir && !isempty(subdir) ? LicenseTableEltype[] : find_licenses(dir)
    if isdir(pkgdir)
        if !isempty(subdir)
            # Look for licenses at top-level and in the subdirectory
            subdir_licenses_files = [(; license_filename=joinpath(subdir, row.license_filename), row.licenses_found, row.license_file_percent_covered) for row in find_licenses(pkgdir)]
            license_files = [subdir_licenses_files; license_files]
        end
        lines_of_code = count_loc(pkgdir)
    else
        license_files = LicenseTableEltype[]
        lines_of_code = LoCTableEltype[]
    end

    if isdir(pkgdir)
        tree_hash = bytes2hex(Pkg.GitTools.tree_hash(pkgdir))
    else
        tree_hash = ""
    end

    # If the repository is on GitHub and we have a non-anonymous GitHub
    # authentication, get the list of contributors
    contributors = if !(auth isa GitHub.AnonymousAuth) && occursin("github.com", repo)
        Base.sleep(sleep)
        repo_name = replace(replace(repo, r"^https://github\.com/" => ""), r"\.git$" => "")
        contribution_table(repo_name; auth)
    else
        ContributionTableElType[]
    end

    Package(name, uuid, repo; subdir, reachable, docs, runtests, travis, appveyor, cirrus,
            circle, drone, buildkite, azure_pipelines, gitlab_pipeline, github_actions,
            license_files, licenses_in_project, lines_of_code, contributors, version, tree_hash)
end


"""
    analyze_path!(dest::AbstractString, repo::AbstractString; name="", uuid=UUID(UInt128(0)), subdir="", auth=github_auth(), sleep=0, tree_hash=nothing) -> Package

Analyze the Julia package located at the URL given by `repo` by cloning it to `dest`
and calling `analyze_path(dest)`. If `tree_hash !== nothing`, only the code associated
to that tree hash is placed into `dest`. That allows analyzing particular version numbers,
but in the case of packages in subdirectories, it also means that top-level information
(like CI workflows) is unavailable.

If the clone fails, it returns a `Package` with `reachable=false`. If a `name` and `uuid` are provided,
these are used to populate the corresponding fields of the `Package`. If the clone succeeds, the `name`
and `uuid` are taken instead from the Project.toml in the package itself, and the values passed here
are ignored.

If the GitHub authentication `auth` is non-anonymous and the repository is on
GitHub, the list of contributors to the repository is also collected, after
waiting for `sleep` seconds for each entry.  See
[`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.
"""
function analyze_path!(dest::AbstractString, repo::AbstractString; name="", uuid=UUID(UInt128(0)), subdir="", auth=github_auth(), sleep=0, tree_hash=nothing, version=v"0")
    isdir(dest) || mkpath(dest)
    only_subdir = false
    reachable = try
        # Clone only latest commit on the default branch.  Note: some
        # repositories aren't reachable because the author made them private or
        # deleted them.  In these cases git would ask for username and password,
        # so we close STDIN to prevent git from prompting for username/password.
        # We need to use `detach` to make closing STDIN effective, suggested by
        # @staticfloat.
        if tree_hash === nothing
            run(pipeline(detach(`$(git()) clone -q --depth 1 $(repo) $(dest)`); stdin=devnull, stderr=devnull))
        else
            m = match(r"github.com/(?<user>.*)/(?<repo>.*)\.git", repo)
            if m !== nothing
                @debug "Downloading code via github api"
                github_extract_code!(dest, m[:user], m[:repo], tree_hash; auth)
            else
                @debug "Falling back to full clone"
                tmp = mktempdir()
                run(pipeline(detach(`$(git()) clone -q $(repo) $(tmp)`); stdin=devnull, stderr=devnull))
                Tar.extract(Cmd(`git archive $tree_hash`; dir=tmp), dest)
            end
            # Either way, we've only put the subdir code into `dest`
            only_subdir = true
        end
        true
    catch e
        @debug "Error; maybe unreachable" exception = e
        # The repository may be unreachable
        false
    end
    return reachable ? analyze_path(dest; repo, reachable, subdir, auth, sleep, only_subdir, version) : Package(name, uuid, repo; subdir, version)
end
