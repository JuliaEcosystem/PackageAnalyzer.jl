function active_manifest()
    project = Base.active_project()
    if !isfile(project)
        error("Project file should exist, but it doesn't: $(project)")
    end
    proj_dir = dirname(project)
    possible_manifests = joinpath.(Ref(proj_dir), Base.manifest_names)
    actual_manifests = filter(isfile, possible_manifests)
    if length(actual_manifests) == 0
        error("No manifest files found in project directory: $(actual_manifests)")
    end
    manifest = first(actual_manifests)
    @debug "active_manifest()=$(manifest)"
    return manifest
end

my_manifest = active_manifest()
all_pkgs = PackageAnalyzer.find_packages_in_manifest(my_manifest)
jll_pkgs = filter(x -> endswith(x.name, "_jll"), all_pkgs)

artifact_hash_to_licenses = Dict{Base.SHA1,Vector{PackageAnalyzer.ArtifactLicenseInfo}}()

PackageAnalyzer.generate_artifact_hash_to_licenses!(
    artifact_hash_to_licenses,
    jll_pkgs;
    allow_no_artifacts=Base.PkgId[],
)

pkgid_to_licenses = PackageAnalyzer.artifact_license_map(
    jll_pkgs,
    artifact_hash_to_licenses;
    allow_no_artifacts=Base.PkgId[],
)

@testset "Artifact licenses (JLLs)" begin
    @test !isempty(pkgid_to_licenses)

    my_list_of_expected_licenses = [
        "Apache-2.0",
        "BSD-2-Clause",
        "BSD-3-Clause",
        "GPL-2.0",
        "GPL-3.0",
        "GPL-3.0-or-later",
        "ISC",
        "LGPL-2.0-or-later",
        "MIT",
        "SSH-OpenSSH",
    ]
    if Sys.iswindows()
        windows_specific_list = [
            "0BSD",
            "CC-BY-SA-3.0",
            "CC0-1.0",
            "GPL-2.0-or-later",
            "LGPL-2.1",
            "LGPL-2.1-or-later",
            "LGPL-3.0",
            "MPL-2.0",
            "RSA-MD",
            "Zlib",
            "bzip2-1.0.6",
            "curl",
        ]
        append!(my_list_of_expected_licenses, windows_specific_list)
    end
    unique!(my_list_of_expected_licenses)
    sort!(my_list_of_expected_licenses)


    my_list_of_actually_observed_licenses = String[]

    for (pkgid, original_licenses) in pairs(pkgid_to_licenses)
        if isempty(original_licenses)
            @error "No licenses found" pkgid original_licenses
            @test !isempty(original_licenses)
        else
            licenses_collapsed = reduce(vcat, [x.licenses_found for x in original_licenses])
            unique!(licenses_collapsed)
            sort!(licenses_collapsed)

            if licenses_collapsed ⊈ my_list_of_expected_licenses
                println()
                @info "Artifact contains unexpected licenses" pkgid join(licenses_collapsed, ',')
                @test_broken false
            end
            @test licenses_collapsed ⊆ my_list_of_expected_licenses

            append!(my_list_of_actually_observed_licenses, licenses_collapsed)
        end
    end

    sort!(my_list_of_actually_observed_licenses)
    unique!(my_list_of_actually_observed_licenses)

    if my_list_of_actually_observed_licenses != my_list_of_expected_licenses
        @error "" join(my_list_of_actually_observed_licenses, ',') join(my_list_of_expected_licenses, ',')
    end
    # We want to test that we are actually finding the licenses that we know we should
    # be finding:
    @test my_list_of_actually_observed_licenses == my_list_of_expected_licenses
end;
