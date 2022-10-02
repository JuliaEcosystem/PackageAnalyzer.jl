# Functions that yield `PkgSource`'s or collections of them

"""
    find_packages(; registries=reachable_registries())) -> Vector{PkgSource}
    find_packages(names::AbstractString...; registries=reachable_registries()) -> Vector{PkgSource}
    find_packages(names; registries=reachable_registries()) -> Vector{PkgSource}

Find all packages in the given registry (specified by the `registry` keyword
argument), the General registry by default. Return a vector of
[`PkgSource`](@ref) pointing to to the directories of each package in the
registry.

Pass a list of package `names` as the first argument to return the paths corresponding to those packages,
or individual package names as separate arguments.
"""
find_packages

find_packages(names::AbstractString...; registries=reachable_registries(), version::Union{VersionNumber, Symbol}=:stable) = find_packages(names; registries, version)

function find_packages(names; registries=reachable_registries(), version::Union{VersionNumber, Symbol}=:stable)
    entries = Release[]
    for name in names
        # Skip stdlibs
        name in values(STDLIBS) && continue
        entry = find_package(name; registries, strict=false, version)
        if entry !== nothing
            push!(entries, entry)
        end
    end
    return entries
end

function get_uuids(uuid::UUID, registry)
    return haskey(registry.pkgs, uuid) ? [uuid] : UUID[]
end

function get_uuids(name::AbstractString, registry)
    return uuids_from_name(registry, name)
end

"""
    find_package(name_or_uuid::Union{AbstractString, UUID}; registries=reachable_registries(), version::Union{VersionNumber,Nothing}=nothing, strict=true, warn=true) -> PkgSource

Returns the [PkgSource](@ref) for the package `pkg`.

* registries: a collection of `RegistryInstance` to look in
* `version`: if `nothing`, finds the maximum registered version in any registry. Otherwise looks for that version number.
* If `strict` is true, errors if the package cannot be found. Otherwise, returns `nothing`.
* If `warn` is true, warns if the package cannot be found. 

See also:  [`find_packages`](@ref).
"""
function find_package(name_or_uuid::Union{AbstractString, UUID}; registries=reachable_registries(), version::Union{VersionNumber, Symbol}=:stable, strict=true, warn=true)
    if version isa Symbol
        if version ∉ (:stable, :dev)
            error("Unrecognized version $version. Either pass a `VersionNumber` or `:stable` or `:dev`.")
        end
    end
    no_version_msg = "Could not find version $version for package $name_or_uuid"

    local_entries = PkgEntry[]
    for registry in registries
        uuids = get_uuids(name_or_uuid, registry)
        if length(uuids) > 1
            error("There are more than one packages with name $(name_or_uuid)! These have UUIDs $uuids")
        elseif length(uuids) == 1
            entry = registry.pkgs[only(uuids)]
            push!(local_entries, entry)
        end
    end
    if isempty(local_entries)
        msg = "Could not find package $name in any registry!"
        if strict
            error(msg)
        elseif warn
            @error(msg)
        end
        return nothing
    elseif length(local_entries) == 1
        entry = only(local_entries)
        if version === :stable
            return Release(entry, max_version(entry))
        elseif version isa VersionNumber
            info = registry_info(entry)
            if !haskey(info.version_info, version)
                strict && error(no_version_msg)
                warn && @error(no_version_msg) 
                return nothing
            end
            return Release(entry, version)
        else # dev
            info = registry_info(entry)
            return Trunk(; repo_url=info.repo, subdir=something(info.subdir, ""))
        end
    else
        # We found the package in multiple registries
        # We want to use the entry associated to the registry
        # with the highest version number if `version==nothing`
        if version === :stable || version === :dev
            infos = registry_info.(entries)
            max_versions = [maximum(keys(info.version_info)) for info in infos]
            idx = argmax(max_versions)
            if version === :stable
                return Release(entries[idx], max_versions[idx])
            else
                entry = entries[idx]
                info = registry_info(entry)
                return Trunk(; repo_url=info.repo, subdir=something(info.subdir, ""))
            end
        else
            infos = registry_info.(entries)
            idx = findfirst(info -> haskey(info.version_info, version), infos)
            if idx === nothing
                strict && error(no_version_msg)
                warn && @error(no_version_msg) 
                return nothing
            end
            entry = entries[idx]
            info = registry_info(info)
            return Release(entry, version)
        end
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
        entries = values(Base.filter(filter, registry.pkgs))
        append!(results, Release.(entries, max_version.(entries)))
    end
    return results
end


function max_version(entry::PkgEntry)
    return maximum(keys(registry_info(entry).version_info))
end

function find_packages_in_manifest(; kw...)
    manifest_path = joinpath(dirname(Base.active_project()), "Manifest.toml")
    return find_packages_in_manifest(manifest_path; kw...)
end

"""
    find_packages_in_manifest([path_to_manifest]; registries=reachable_registries(),
                              strict=true, warn=true)) -> Vector{PkgSource}

Returns `Vector{PkgSource}` associated to all of the package/version combinations stored in a Manifest.toml.

* `path_to_manifest` defaults to `joinpath(dirname(Base.active_project()), "Manifest.toml")`
* registries: a collection of `RegistryInstance` to look in
* `strict` and `warn` have the same meaning as in [`find_package`](@ref).
* Standard libraries are always skipped, without warning or errors.

"""
function find_packages_in_manifest(path_to_manifest; registries=reachable_registries(), strict=true, warn=true)
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
            pkg = find_package(uuid; version, registries, strict, warn)            
            if pkg === nothing
                continue
            end

            lookup = registry_info(pkg.entry).version_info[version]
            tree_hash_from_registry = bytes2hex(lookup.git_tree_sha1.bytes)
            if tree_hash_from_registry != manifest_tree_hash
                error("Somehow `tree_hash_from_registry`=$(tree_hash_from_registry) does not match `manifest_tree_hash`=$(manifest_tree_hash)")
            end
            push!(results, pkg)
        end
    end
    return results
end