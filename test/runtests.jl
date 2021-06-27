using Test, UUIDs
using PackageAnalyzer
using PackageAnalyzer: parse_project, RegistryEntry
using JLLWrappers
using GitHub

get_libpath() = get(ENV, JLLWrappers.LIBPATH_env, nothing)
const orig_libpath = get_libpath()

const auth = GitHub.AnonymousAuth()

@testset "PackageAnalyzer" begin
    general = general_registry()
    @test isdir(general)
    @test all(p -> isdir(p.path), find_packages())
    @test find_package("julia") ∉ find_packages()
    @test all(p -> isdir(p.path), find_packages("Flux"))
    @test isdir(find_package("Flux").path)
    # Test some properties of the `Measurements` package.  NOTE: they may change
    # in the future!
    measurements = analyze(RegistryEntry(joinpath(general, "M", "Measurements")); auth)
    @test measurements.uuid == UUID("eff96d63-e80a-5855-80a2-b1b0885c5ab7")
    @test measurements.reachable
    @test measurements.docs
    @test measurements.runtests
    @test !measurements.buildkite
    @test !isempty(measurements.lines_of_code)
    # Test results of a couple of packages.  Same caveat as above
    packages = [RegistryEntry(joinpath(general, p...)) for p in (("C", "Cuba"), ("P", "PolynomialRoots"))]
    @test Set(packages) == Set(find_packages("Cuba", "PolynomialRoots")) == Set(find_packages(["Cuba", "PolynomialRoots"]))
    @test packages ⊆ find_packages()
    results = analyze(packages; auth)
    cuba, polyroots = results
    @test length(filter(p -> p.reachable, results)) == 2
    @test length(filter(p -> p.runtests, results)) == 2
    @test cuba.drone
    @test !polyroots.docs # Documentation is in the README!
    # We can also use broadcasting!
    @test Set(results) == Set(analyze.(packages; auth))

    # Test `analyze!` directly
    mktempdir() do root
        measurements2 = analyze!(root, RegistryEntry(joinpath(general, "M", "Measurements")); auth)
        @test isequal(measurements, measurements2)
        @test isdir(joinpath(root, "eff96d63-e80a-5855-80a2-b1b0885c5ab7")) # not cleaned up yet
    end
end

@testset "`analyze`" begin
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
    bad_pkg = analyze("."; auth)
    @test bad_pkg.repo == ""
    @test bad_pkg.uuid == UUID(UInt128(0))
    @test !bad_pkg.cirrus
    @test isempty(bad_pkg.license_files)
    @test isempty(bad_pkg.licenses_in_project)

    # The argument is a package name
    pkg = analyze("Pluto"; auth)
    # Just make sure we got the UUID correctly and some statistics are collected.
    @test pkg.uuid == UUID("c3e4b0f8-55cb-11ea-2926-15256bba5781")
    @test !isempty(pkg.license_files)
    @test !isempty(pkg.lines_of_code)
    # The argument looks like a package name but it isn't a registered package
    @test_logs (:error, r"Could not find package in registry") match_mode=:any @test_throws ArgumentError analyze("license_in_project"; auth)
end

@testset "`find_packages` with `analyze`" begin
    results = analyze(find_packages("DataFrames", "Flux"); auth) # this method is threaded
    @test results isa Vector{PackageAnalyzer.Package}
    @test length(results) == 2
    # DataFrames currently has 16k LoC; Flux has 5k. Let's check that they aren't mixed up
    # due to some kind of race condition.
    @test results[1].name == "DataFrames"
    @test PackageAnalyzer.count_julia_loc(results[1].lines_of_code, "src") > 14000
    @test results[2].name == "Flux"
    @test PackageAnalyzer.count_julia_loc(results[2].lines_of_code, "src") < 14000


    results = analyze(find_packages("DataFrames"); auth)
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
    @test_throws ErrorException("Could not find standard library Dates in registry") find_package("Dates")
    @test_throws ErrorException("Could not find Abc in registry") find_package("Abc")
end

@testset "`analyze_path!`" begin
    # we check the error path here; the success path is covered by other tests.
    # This also makes sure trying to clone the repo doesn't prompt for
    # username/password
    result = PackageAnalyzer.analyze_path!(mktempdir(), "https://github.com/giordano/DOES_NOT_EXIST.jl"; auth)
    @test result isa PackageAnalyzer.Package
    @test !result.reachable
    @test isempty(result.name)
end

@testset "`subdir` support" begin
    snoop_core_path = only(find_packages("SnoopCompileCore"))
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
    snoop_compile = analyze(find_package("SnoopCompile"); auth)
    snoop_compile_count_for_core = sum(row.code for row in snoop_compile.lines_of_code if row.language == :Julia && row.sublanguage===nothing && row.directory == "SnoopCompileCore")
    snoop_core_count = sum(row.code for row in snoop_core.lines_of_code if row.language == :Julia && row.sublanguage===nothing)
    @test snoop_core_count == snoop_compile_count_for_core

    # this package doesn't exist in the repo anymore; let's ensure it doesn't throw
    snoop_compile_analysis = analyze(find_package("SnoopCompileAnalysis"); auth)
    @test isempty(snoop_compile_analysis.lines_of_code)
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
    @test parse_project("license_in_project") == project_1

    # has `license = ["MIT", "GPL"]`
    project_2 = (; name = "PackageAnalyzer", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project=["MIT", "GPL"])
    @test parse_project("licenses_in_project") == project_2
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
        @test PackageAnalyzer.count_contributors(pkg; type="Anonymous") > 10
    end
end

@testset "Thread-safety" begin
    # Make sure none of the above commands leaks LD_LIBRARY_PATH.  This test
    # should be executed at the very end of the test suite.
    @test orig_libpath == get_libpath()
end
