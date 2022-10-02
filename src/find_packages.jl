# Functions that yield `PkgSource`'s or collections of them
"""
    find_package(pkg; registries=reachable_registries(), version::Union{VersionNumber, Nothing}=nothing) -> PkgEntry

Returns the [RegistryEntry](@ref) for the package `pkg`.
The singular version of [`find_packages`](@ref).
"""
function find_package(pkg::AbstractString; registries=reachable_registries(), version::Union{VersionNumber, Nothing}=nothing)
    pkg_entries = find_packages([pkg]; registries, version)
    if isempty(pkg_entries)
        if pkg ∈ values(STDLIBS)
            throw(ArgumentError("Standard library $pkg not present in registry"))
        else
            throw(ArgumentError("$pkg not found in registry"))
        end
    end
    return only(pkg_entries)
end

"""
    find_packages(; registries=reachable_registries())) -> Vector{PkgEntry}
    find_packages(names::AbstractString...; registries=reachable_registries()) -> Vector{PkgEntry}
    find_packages(names; registries=reachable_registries()) -> Vector{PkgEntry}

Find all packages in the given registry (specified by the `registry` keyword
argument), the General registry by default. Return a vector of
[RegistryEntry](@ref) pointing to to the directories of each package in the
registry.

Pass a list of package `names` as the first argument to return the paths corresponding to those packages,
or individual package names as separate arguments.
"""
find_packages

find_packages(names::AbstractString...; registries=reachable_registries(), version::Union{VersionNumber, Nothing}=nothing) = find_packages(names; registries, version)

function find_packages(names; registries=reachable_registries(), version::Union{VersionNumber, Nothing}=nothing)
    if names !== nothing
        entries = Release[]
        for name in names
            local_entries = PkgEntry[]
            for registry in registries
                uuids = uuids_from_name(registry, name)
                if length(uuids) > 1
                    error("There are more than one packages with name $(name)! These have UUIDs $uuids")
                elseif length(uuids) == 1
                    entry = registry.pkgs[only(uuids)]
                    push!(local_entries, entry)
                end
            end
            if isempty(local_entries) && name ∉ values(STDLIBS)
                @error("Could not find package in registry!", name)
            elseif length(local_entries) == 1
                push!(entries, Release(only(local_entries), version))
            else
                # We found the package in multiple registries
                # We want to use the entry associated to the registry
                # with the highest version number if `version==nothing`
                if version === nothing
                    infos = registry_info.(entries)
                    max_versions = [maximum(keys(info.version_info)) for info in infos]
                    idx = argmax(max_versions)
                    entry = entries[idx]
                else
                    infos = registry_info.(entries)
                    idx = findfirst(info -> haskey(info.version_info, version), infos)
                    if idx === nothing
                        error("")
                    end
                    entry = entries[idx]
                end
                push!(entries, Release(entry, version))
            end
        end
        return entries
    end
end

# The UUID of the "julia" pseudo-package in the General registry
const JULIA_UUID = UUID("1222c4b2-2114-5bfd-aeef-88e4692bbb3e")

function find_packages(; registries=reachable_registries(),
    filter=((uuid, p),) -> !endswith(p.name, "_jll") && uuid != JULIA_UUID)
    results = Release[]
    # Get the PkgEntry's of all packages in the registry.  Filter out JLL packages: they are
    # automatically generated and we know that they don't have testing nor
    # documentation. We also filter out the "julia" package which is not a real
    # package and just points at the Julia source code.
    for registry in registries
        append!(results, Release.(values(Base.filter(filter, registry.pkgs)), Ref(nothing)))
    end
    return results
end

function match_pkg(uuid, version, registries)
    for r in registries
        haskey(r.pkgs, uuid) || continue
        # Ok the registry has the package. Does it have the version we need?
        pkg = r.pkgs[uuid]
        info = registry_info(pkg)
        haskey(info.version_info, version) || continue
        # Yes it does
        return pkg
    end
    return nothing
end

function find_packages_in_manifest(; kw...)
    manifest_path = joinpath(dirname(Base.active_project()), "Manifest.toml")
    return find_packages_in_manifest(manifest_path; kw...)
end

function find_packages_in_manifest(path_to_manifest; registries=reachable_registries())
    manifest = TOML.parsefile(path_to_manifest)
    format = parse(VersionNumber, get(manifest, "manifest_format", "1.0"))
    if format.major == 2
        pkgs = manifest["deps"]
    elseif format.major == 1
        pkgs = manifest
    else
        error("Unsupported Manifest format $format")
    end
    results = PkgSource[]
    for (name, list) in pkgs
        for manifest_entry in list
            uuid = UUID(manifest_entry["uuid"]::String)
            if uuid in keys(STDLIBS)
                continue
            end
            manifest_tree_hash = get(manifest_entry, "git-tree-sha1", "")::String
            # Option 1: No tree-hash. Then we're dev'd.
            if isempty(manifest_tree_hash) # dev
                # This should always exist, in the dev case
                # (dev-from-url clones then devs the local path)
                path = manifest_entry["path"]::String
                # Note: we may or may not be in a subdir, we cannot know!
                # The path will be all the way to the subdir package
                push!(results, Dev(; name, uuid, path))
                continue
            end
            # Option 2: has repo-url (could be local path)
            # Then we're `Added`
            repo_url = get(manifest_entry, "repo-url", "")::String
            if !isempty(repo_url)
                if isdir(repo_url) # local
                    path = repo_url
                    repo_url = ""
                else
                    path = ""
                end
                subdir = get(manifest_entry, "repo-subdir", "")::String

                push!(results, Added(; name, uuid, path, repo_url, tree_hash=manifest_tree_hash, subdir))
                continue
            end

            # Option 3: Release package

            version = VersionNumber(manifest_entry["version"]::String)
            pkg = match_pkg(uuid, version, registries)
            
            if pkg === nothing
                @error("Could not find (package, version) pair in any registry!", name, uuid, version)
                continue
            end

            lookup = registry_info(pkg).version_info[version]
            tree_hash_from_registry = bytes2hex(lookup.git_tree_sha1.bytes)
            if tree_hash_from_registry != manifest_tree_hash
                error()
            end
            
            push!(results, Release(pkg, version))
        end
    end
    return results
end
