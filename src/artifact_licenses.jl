# Structually, ArtifactLicenseInfo is the same as the "original license info". But I made it
# a different type because I want to do "nominal typing", that is, I want to semantically
# distinguish between artifact licenses and Julia package licenses.
#
# That is, the public interface for this functionality is a function named
# PackageAnalyzer.artifact_license_map(). This function
# returns a dict, where the keys of the dict are packages (specifically, the keys are Base.PkgIds,
# which simply contain the package name and the package UUID), and the value is the artifact
# license information. The artifact license information is not the same as the license for the
# Julia package source code itself, so I don't want to confuse the user. I want to make it clear
# that the user is only getting (from this function) the licenses for the artifacts. So that's
# why I chose to return ArtifactLicenseInfos.
#
# In contrast, if I just returned the named tuple of
# (; license_filename::String, licenses_found::Vector{String}, license_file_percent_covered::Float64),
# then it would not be clear whether the user was working with the licenses from artifacts or
# the Julia package source code itself. So, using a nominal ArtifactLicenseInfo type makes it
# more clear, and also prevents the user from accidentally combining the two.
#
Base.@kwdef struct ArtifactLicenseInfo
    license_filename::String
    licenses_found::Vector{String}
    license_file_percent_covered::Float64
end

_get_pkg_uuid_u(pkg::Release) = Base.UUID(pkg.uuid)
_get_pkg_uuid_u(pkg::Added) = Base.UUID(pkg.uuid)

_get_pkg_name(pkg::Release) = pkg.name
_get_pkg_name(pkg::Added) = pkg.name

function _construct_pkgid(pkg::PkgSource)
    name = _get_pkg_name(pkg)
    uuid_u = _get_pkg_uuid_u(pkg)
    id = Base.PkgId(uuid_u, name)
    return id
end

# Take in a directory local_dir.
# Return all of the Artifacts.toml (and JuliaArtifacts.toml) files that we find when we search
# the local_dir directory recursively.
function find_artifacts_toml_from_local_dir(local_dir::String)
    artifacts_toml_files = String[]
    for (root, dirs, files) in walkdir(local_dir)
        for name in files
            if name in Artifacts.artifact_names
                full_path = joinpath(root, name)
                push!(artifacts_toml_files, full_path)
            end
        end
    end
    return artifacts_toml_files
end

_get_git_tree_sha1(x::Pair) = _get_git_tree_sha1(Dict(x))
_get_git_tree_sha1(x::Dict) = Base.SHA1(x["git-tree-sha1"])

# Take in the "info" from an Artifacts.toml file.
# Return all possible artifact hashes (git-tree-sha1).
# Note: This covers the hashes for all platforms (not just the user's current platform).
_get_possible_artifact_hashes_from_info(info::Dict) = [_get_git_tree_sha1(info)]
function _get_possible_artifact_hashes_from_info(info::Vector)
    return _get_git_tree_sha1.(info)
end

# Take in the filename of an Artifacts.toml file.
# Return all possible artifact hashes (git-tree-sha1).
# Note: This covers the hashes for all platforms (not just the user's current platform).
function get_possible_artifact_hashes_from_artifacts_toml(artifacts_toml::String)
    possible_hashes = Base.SHA1[]
    artifacts_dict = TOML.parsefile(artifacts_toml)
    for (name, info) in pairs(artifacts_dict)
        vec = _get_possible_artifact_hashes_from_info(info)
        append!(possible_hashes, vec)
    end
    unique!(possible_hashes)
    return possible_hashes
end

# Take in the directory local_dir where a package lives.
# Return all possible artifact hashes (git-tree-sha1).
# Note: This covers the hashes for all platforms (not just the user's current platform).
function get_possible_artifact_hashes_from_local_dir(local_dir::String; pkg)
    artifacts_toml_files = find_artifacts_toml_from_local_dir(local_dir)
    if isempty(artifacts_toml_files)
        msg = "Did not find any {,Julia}Artifacts.toml files for package: $(pkg)"
        error(msg)
    end
    possible_hashes = get_possible_artifact_hashes_from_artifacts_toml.(artifacts_toml_files) |> Iterators.flatten |> collect
    unique!(possible_hashes)
    return possible_hashes
end

# Take in an artifact hash (git-tree-sha1).
# Return all of the licenses that we find.
function get_licenses_from_artifact_hash(hash::Base.SHA1)
    artifact_root_path = Artifacts.artifact_path(hash)
    licenses = ArtifactLicenseInfo[]
    for (root, dirs, files) in walkdir(artifact_root_path)
        for dir in dirs
            full_path = joinpath(root, dir)
            found = LicenseCheck.find_license(full_path)
            if !isnothing(found)
                new_info = ArtifactLicenseInfo(;
                    found.license_filename,
                    found.licenses_found,
                    found.license_file_percent_covered,
                )
                push!(licenses, new_info)
            end
        end
    end
    unique!(licenses)
    if isempty(licenses)
        msg = "No licenses found for artifact $(hash)"
        @error msg
    end
    return licenses
end

# Takes in two arguments:
# 1. artifact_hash_to_licenses: a dict where the keys are artifact hashes (git-tree-sha1)
#                               and the values are lists of licenses.
# 2. available_hashes: a list of artifact hashes (git-tree-sha1)
#
# This function goes through the list of hashes in available_hashes.
# For each hash in available_hashes, the function gets the list of all licenses, and then
# mutates the dict artifact_hash_to_licenses to set
# artifact_hash_to_licenses[$hash] = $listoflicenses
function generate_artifact_hash_to_licenses!(
    artifact_hash_to_licenses::Dict{Base.SHA1,Vector{ArtifactLicenseInfo}},
    available_hashes::Vector{Base.SHA1},
)
    for hash in available_hashes
        licenses = get_licenses_from_artifact_hash(hash::Base.SHA1)
        artifact_hash_to_licenses[hash] = licenses
    end
    return nothing
end

# Takes in two arguments:
# 1. artifact_hash_to_licenses: a dict where the keys are artifact hashes (git-tree-sha1)
#    and the values are lists of licenses.
# 2. pkgs: a list of PkgSources.
#
# This function goes through the list of packages in pkgs.
# For each pkg in pkgs, the function gets the list of all available artifact hashes for that
# package, and then for each of those artifact hashes, get the list of licenses. Then, for each
# artifact hash, mutate the dict artifact_hash_to_licenses to set
# artifact_hash_to_licenses[$hash] = $listoflicenses
#
# Keyword arguments:
# 1. allow_no_artifacts::Vector{Base.PkgId}. If a package has no artifacts, then we throw an
#    error if the package is not in the allow_no_artifacts list, but we print a debug message
#    (and don't throw an error) if the package is in the allow_no_artifacts list.
function generate_artifact_hash_to_licenses!(
    artifact_hash_to_licenses::Dict{Base.SHA1,Vector{ArtifactLicenseInfo}},
    pkgs::Vector{<:PkgSource};
    kwargs...,
)
    available_hashes = Base.SHA1[]
    for pkg in pkgs
        hashes = generate_available_artifact_hashes_from_pkg(pkg::PkgSource; kwargs...)
        append!(available_hashes, hashes)
    end
    generate_artifact_hash_to_licenses!(artifact_hash_to_licenses, available_hashes;)
    return nothing
end

# Take in a PkgSource.
# Return all possible artifact hashes for this package.
function generate_possible_artifact_hashes_from_pkg(pkg::PkgSource)
    this_pkgid = _construct_pkgid(pkg)
    local_dir, reachable, version, _ = PackageAnalyzer.obtain_code(pkg)
    if !reachable
        msg = "Package is not reachable: $(pkg)"
        error(msg)
    end
    possible_hashes = get_possible_artifact_hashes_from_local_dir(local_dir::String; pkg)
    return possible_hashes
end

# Take in a PkgSource.
# Return all available artifact hashes for this package. Note: This is the list of available
# artifact hashes, not the list of all possible artifact hashes. The difference is this:
# - Possible artifact hash = the hash is in the Artifacts.toml file, but it might be for a platform
#                            that is different from the current platform.
# - Available artifact hash = the hash actually exists locally (which means that the artifact's
#                             platform is the same as the current platform.)
#
# Keyword arguments:
# 1. allow_no_artifacts::Vector{Base.PkgId}. Same as documented above.
function generate_available_artifact_hashes_from_pkg(
    pkg::PkgSource;
    allow_no_artifacts::Vector{Base.PkgId} = Base.PkgId[],
)
    this_pkgid = _construct_pkgid(pkg)
    possible_hashes = generate_possible_artifact_hashes_from_pkg(pkg)
    available_hashes = filter(Artifacts.artifact_exists, possible_hashes)
    unique!(available_hashes)
    if isempty(available_hashes)
        msg = "No artifacts were found for package $(pkg) with PkgId $(this_pkgid)"
        if this_pkgid in allow_no_artifacts
            @debug msg
        else
            error(msg)
        end
    end
    return available_hashes
end

# Takes in a list of PkgSource.
# Returns a dict pkgid_to_licenses.
# The key of pkgid_to_licenses are Base.PkgId.
# The value of pkgid_to_licenses is the list of licenses for that package.
function generate_pkgid_to_licenses(pkgs::Vector{<:PkgSource}; kwargs...)
    artifact_hash_to_licenses = Dict{Base.SHA1,Vector{ArtifactLicenseInfo}}()
    generate_artifact_hash_to_licenses!(artifact_hash_to_licenses, pkgs; kwargs...)
    pkgid_to_licenses = artifact_license_map(pkgs, artifact_hash_to_licenses; kwargs...)
    return pkgid_to_licenses
end

# Takes in two arguments:
# 1. pkgs: list of PkgSources.
# 2. artifact_hash_to_licenses: this is the :Dict{Base.SHA1,Vector{ArtifactLicenseInfo}}
#    that we get after running the following:
#      - artifact_hash_to_licenses = Dict{Base.SHA1,Vector{ArtifactLicenseInfo}}()
#      - generate_artifact_hash_to_licenses!(artifact_hash_to_licenses, pkgs; kwargs...)
#
# Keyword arguments:
# 1. allow_no_artifacts::Vector{Base.PkgId}. Same as documented above.
function artifact_license_map(
    pkgs::Vector{<:PkgSource},
    artifact_hash_to_licenses::Dict{Base.SHA1,Vector{ArtifactLicenseInfo}};
    kwargs...,
)
    pkguuid_to_licenses = Dict{Base.PkgId,Vector{ArtifactLicenseInfo}}()
    for pkg in pkgs
        licenses_for_this_pkg = ArtifactLicenseInfo[]
        hashes = generate_available_artifact_hashes_from_pkg(pkg::PkgSource; kwargs...)
        for hash in hashes
            licenses_for_this_hash = artifact_hash_to_licenses[hash]
            append!(licenses_for_this_pkg, licenses_for_this_hash)
        end
        pkguuid_to_licenses[_construct_pkgid(pkg)] = licenses_for_this_pkg
    end
    return pkguuid_to_licenses
end
