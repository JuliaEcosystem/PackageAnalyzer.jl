using Test, UUIDs
using PackageAnalyzer
using PackageAnalyzer: parse_project, Release, Added, Dev, Trunk, PkgSource
using JLLWrappers
using GitHub: GitHub
using RegistryInstances

get_libpath() = get(ENV, JLLWrappers.LIBPATH_env, nothing)
const orig_libpath = get_libpath()

const auth = GitHub.AnonymousAuth()

@testset "PackageAnalyzer" begin
    @testset "Basic" begin
        # Test some properties of the `Measurements` package.  NOTE: they may change
        # in the future!
        pkg = find_package("Measurements")
        @test pkg isa Release # we should be defaulting to the latest release
        measurements = analyze(pkg; auth)
        @test measurements.uuid == UUID("eff96d63-e80a-5855-80a2-b1b0885c5ab7")
        @test measurements.reachable
        @test measurements.docs
        @test measurements.runtests
        @test !isempty(measurements.tree_hash)
        @test !measurements.buildkite
        @test !isempty(measurements.lines_of_code)
        packages = find_packages("Cuba", "PolynomialRoots")
        # Test results of a couple of packages.  Same caveat as above
        # We compare by UUID + version, since other fields may be initialized or not
        fields = [(p.entry.uuid, p.version) for p in packages]
        fields2 = [(p.entry.uuid, p.version) for p in find_packages(["Cuba", "PolynomialRoots"])]
        @test issetequal(fields, fields2)
        @test first.(fields) ⊆ [x.entry.uuid for x in find_packages()]
        results = analyze_packages(packages; auth)
        cuba, polyroots = results
        @test length(filter(p -> p.reachable, results)) == 2
        @test length(filter(p -> p.runtests, results)) == 2
        @test cuba.cirrus
        @test !polyroots.docs # Documentation is in the README!
        # We can also use broadcasting!
        fields = [(p.uuid, p.tree_hash) for p in results]
        fields2 = [(p.uuid, p.tree_hash) for p in analyze.(packages; auth)]
        @test issetequal(fields, fields2)

        # Test `analyze` with `root` argument specified
        mktempdir() do root
            @test isempty(readdir(root)) # dir starts empty
            measurements2 = analyze(find_package("Measurements"; version=:dev); auth, root)
            @test !isempty(readdir(root)) # code gets downloaded there
            @test measurements2.version === nothing

            measurements3 = analyze(find_package("Measurements"); auth, root)
            @test isequal(measurements, measurements3) # same version, just with a root
            @test measurements.version isa VersionNumber

            measurements4 = analyze(find_package("Measurements"; version=v"2.8.0"); auth, root)
            @test measurements4.version == v"2.8.0"
            @test isdir(joinpath(root, "Measurements", "PwGjt")) # not cleaned up yet
        end
    end

    @testset "find_packages_in_manifest" begin
        pkgs = find_packages_in_manifest(joinpath(pkgdir(PackageAnalyzer), "Manifest.toml"))
        @test pkgs isa Vector{PkgSource}
        few = first(pkgs, 3)
        # Should be all release deps here
        @test all(p -> p isa Release, few)
        results = analyze_packages(few; auth)
        @test length(results) == length(few)
        # Version number saved out
        @test all(results[i].version == few[i].version for i in 1:length(few))
    end

    @testset "`analyze`" begin
        # `dev` analysis:
        for pkg in (analyze(PackageAnalyzer; auth), analyze("https://github.com/giordano/PackageAnalyzer.jl"; auth), analyze(joinpath(@__DIR__, ".."); auth))
            @test pkg.uuid == UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c")
            @test pkg.reachable == true # default
            @test pkg.docs == true
            @test pkg.runtests == true # here we are!
            @test pkg.github_actions == true
            @test length(pkg.license_files) == 1
            @test pkg.license_files[1].licenses_found == ["MIT"]
            @test pkg.license_files[1].license_filename == "LICENSE"
            @test pkg.license_files[1].license_file_percent_covered > 90
            @test pkg.license_files isa Vector{<:NamedTuple}
            @test keys(pkg.license_files[1]) == (:license_filename, :licenses_found, :license_file_percent_covered)
            @test isempty(pkg.licenses_in_project)
            @test !isempty(pkg.lines_of_code)
            @test pkg.lines_of_code isa Vector{<:NamedTuple}
            @test keys(pkg.lines_of_code[1]) == (:directory, :language, :sublanguage, :files, :code, :comments, :blanks)
            idx = findfirst(row -> row.directory=="src" && row.language==:Julia && row.sublanguage===nothing, pkg.lines_of_code)
            @test idx !== nothing
            @test pkg.lines_of_code[idx].code > 200
        end

        # the tests folder isn't a package!
        # But this helps catch issues in error paths for when things go wrong
        bad_pkg = analyze(@__DIR__; auth)
        @test bad_pkg.version === nothing
        @test bad_pkg.uuid == UUID(UInt128(0))
        @test !bad_pkg.cirrus
        @test isempty(bad_pkg.license_files)
        @test isempty(bad_pkg.licenses_in_project)
        @test bad_pkg.version === nothing


        # The argument is a package name
        pkg = analyze("Pluto"; auth, version=:dev)
        @test pkg.version === nothing

        # Just make sure we got the UUID correctly and some statistics are collected.
        @test pkg.uuid == UUID("c3e4b0f8-55cb-11ea-2926-15256bba5781")
        @test !isempty(pkg.license_files)
        @test !isempty(pkg.lines_of_code)
        # The argument looks like a package name but it isn't a registered package
        @test_throws ArgumentError analyze("license_in_project"; auth)

        old = analyze("PackageAnalyzer"; version=v"0.1", auth)
        @test old.version == v"0.1" # we save out the version number
        @test old.tree_hash == "a4cb0648ddcbeb6bc161f87906a0c17c456a27dc"
        @test old.docs == true
        @test old.subdir == ""
        # This shouln't change, unless we change *how* we count LoC, since the code is fixed:
        @test PackageAnalyzer.count_julia_loc(old.lines_of_code, "src") == 549

        root = mktempdir()
        old2 = analyze(find_package("PackageAnalyzer"; version=v"0.1"); auth, root)
        @test isequal(old, old2)

        dev = analyze(find_package("PackageAnalyzer"; version=:dev); auth, root)
        @test !isequal(old, dev) # different

        # Should not re-download or collide w/ dev download
        old3 = analyze(find_package("PackageAnalyzer"; version=v"0.1"); auth, root)
        @test isequal(old, old3)

        stable = analyze(find_package("PackageAnalyzer"; version=:stable); auth, root)
        # For `stable`, we save out the corresponding `VersionNumber`
        @test stable.version isa VersionNumber


    end

    @testset "`find_packages` with `analyze`" begin
        results = analyze_packages(find_packages("DataFrames", "Flux"); auth) # this method is threaded
        @test results isa Vector{PackageAnalyzer.Package}
        @test length(results) == 2
        # DataFrames currently has 16k LoC; Flux has 5k. Let's check that they aren't mixed up
        # due to some kind of race condition.
        @test results[1].name == "DataFrames"
        @test PackageAnalyzer.count_julia_loc(results[1], "src") > 14000
        @test PackageAnalyzer.count_docs(results[1]) > 5000
        @test PackageAnalyzer.count_readme(results[1]) > 5

        @test results[2].name == "Flux"
        @test PackageAnalyzer.count_julia_loc(results[2].lines_of_code, "src") < 14000


        results = analyze_packages(find_packages("DataFrames"); auth)
        @test results isa Vector{PackageAnalyzer.Package}
        @test length(results) == 1
        @test results[1].name == "DataFrames"

        result = analyze(find_package("DataFrames"); auth)
        @test result isa PackageAnalyzer.Package
        @test result.name == "DataFrames"

        # Don't error when not finding stdlibs in `find_packages`
        @test_logs find_packages("Dates")
        # But we do emit a warning log for non-existent package `Abc`
        @test_logs (:error,) find_packages("Abc")

        # Check we get a nice error for `find_package`
        @test_throws ArgumentError("Could not find standard library Dates in any registry!") find_package("Dates")
        @test_throws ArgumentError("Could not find package Abc in any registry!") find_package("Abc")
    end

    @testset "`analyze`" begin
        # we check the error path here; the success path is covered by other tests.
        # This also makes sure trying to clone the repo doesn't prompt for
        # username/password
        result = PackageAnalyzer.analyze("https://github.com/giordano/DOES_NOT_EXIST.jl"; auth)
        @test result isa PackageAnalyzer.Package
        @test !result.reachable
        @test isempty(result.name)
    end

    @testset "`subdir` support" begin
        snoop_core_path = only(find_packages("SnoopCompileCore"; version=:dev))
        snoop_core = analyze(snoop_core_path; auth)
        @test !isempty(snoop_core.subdir)
        @test snoop_core.name == "SnoopCompileCore" # this test would fail if we were parsing the wrong Project.toml (that of SnoopCompile)
        # This tests that we find licenses in the subdir and put them first,
        # and find licenses in the repo dir and put them last.
        @test startswith(snoop_core.license_files[1].license_filename, "SnoopCompileCore")
        @test !startswith(snoop_core.license_files[end].license_filename, "SnoopCompileCore")

        # Let's check we're counting LoC right for subdirectories. We have two ways of counting
        # the Julia code in SnoopCompileCore. One, we can ask SnoopCompile for the lines of Julia code in its
        # top-level directory `SnoopCompileCore`. Two, we can ask SnoopCompileCore for all of it's
        # Julia code.
        snoop_compile = analyze(find_package("SnoopCompile"; version=:dev); auth)
        snoop_compile_count_for_core = sum(row.code for row in snoop_compile.lines_of_code if row.language == :Julia && row.sublanguage===nothing && row.directory == "SnoopCompileCore")
        snoop_core_count = sum(row.code for row in snoop_core.lines_of_code if row.language == :Julia && row.sublanguage===nothing)
        @test snoop_core_count == snoop_compile_count_for_core

        # this package doesn't exist in the repo anymore; let's ensure it doesn't throw
        snoop_compile_analysis = analyze(find_package("SnoopCompileAnalysis"; version=:dev); auth)
        @test isempty(snoop_compile_analysis.lines_of_code)
        @test isempty(snoop_compile_analysis.tree_hash)

        # Note: latest stable release still works!
        snoop_compile_analysis = analyze(find_package("SnoopCompileAnalysis"); auth)
        @test !isempty(snoop_compile_analysis.lines_of_code)
        @test !isempty(snoop_compile_analysis.tree_hash)
    end

    @testset "`parse_project`" begin
        bad_project = (; name="Invalid Project.toml", uuid=UUID(UInt128(0)), licenses_in_project=String[])
        # malformatted TOML file
        @test parse_project("missingquote") == bad_project

        # bad UUID
        @test parse_project("baduuid") == bad_project

        # non-existent folder
        @test parse_project("rstratarstra") == bad_project

        # proper Project.toml
        this_project = (; name = "PackageAnalyzer", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project = String[])
        @test parse_project(joinpath(@__DIR__, "..")) == this_project

        # has `license = "MIT"`
        project_1 = (; name = "PackageAnalyzer", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project=["MIT"])
        @test parse_project(joinpath(@__DIR__, "license_in_project")) == project_1

        # has `license = ["MIT", "GPL"]`
        project_2 = (; name = "PackageAnalyzer", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project=["MIT", "GPL"])
        @test parse_project(joinpath(@__DIR__, "licenses_in_project")) == project_2
    end

    @testset "`show`" begin
        # this is mostly to test that `show` doesn't error
        str = sprint(show, analyze(pkgdir(PackageAnalyzer); auth))
        @test occursin("* uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c", str)
        @test occursin("* OSI approved: true", str)
    end

    @testset "Contributors" begin
        if PackageAnalyzer.github_auth() isa GitHub.AnonymousAuth
            @warn "Skipping contributors tests since `PackageAnalyzer.github_auth()` is anonymous"
        else
            pkg = analyze("DataFrames")
            @test pkg.contributors isa Vector{<:NamedTuple}
            @test length(pkg.contributors) > 160 # ==183 right now, and it shouldn't go down...
            @test PackageAnalyzer.count_contributors(pkg) > 150
            @test PackageAnalyzer.count_commits(pkg) > 2000
            @test PackageAnalyzer.count_contributors(pkg; type="Anonymous") > 10
        end
    end

    @testset "Thread-safety" begin
        # Make sure none of the above commands leaks LD_LIBRARY_PATH.  This test
        # should be executed at the very end of the test suite.
        @test orig_libpath == get_libpath()
    end
end
