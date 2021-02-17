using Test, UUIDs
using AnalyzeRegistry
using AnalyzeRegistry: parse_project

### Doctests
using Documenter, DataFrames
DocMeta.setdocmeta!(AnalyzeRegistry, :DocTestSetup, :(using AnalyzeRegistry); recursive=true)

@testset "Doctests" begin
    # doctests failing?
    # DataFrames or Flux updated their number of lines of code?
    # Not to fear, just run `doctest(AnalyzeRegistry, fix=true)` to update them.
    # (Just have a look at the diff before committing!)
    doctest(AnalyzeRegistry)
end
###

@testset "AnalyzeRegistry" begin
    general = general_registry()
    @test isdir(general)
    @test all(isdir, find_packages())
    @test all(isdir, find_packages("Flux"))
    @test isdir(find_package("Flux"))
    # Test some properties of the `Measurements` package.  NOTE: they may change
    # in the future!
    measurements = analyze_from_registry(joinpath(general, "M", "Measurements"))
    @test measurements.uuid == UUID("eff96d63-e80a-5855-80a2-b1b0885c5ab7")
    @test measurements.reachable
    @test measurements.docs
    @test measurements.runtests
    @test !measurements.buildkite
    @test !isempty(measurements.lines_of_code)
    # Test results of a couple of packages.  Same caveat as above
    packages = [joinpath(general, p...) for p in (("C", "Cuba"), ("P", "PolynomialRoots"))]
    @test Set(packages) == Set(find_packages("Cuba", "PolynomialRoots")) == Set(find_packages(["Cuba", "PolynomialRoots"]))
    @test packages ⊆ find_packages()
    results = analyze_from_registry(packages)
    cuba, polyroots = results
    @test length(filter(p -> p.reachable, results)) == 2
    @test length(filter(p -> p.runtests, results)) == 2
    @test cuba.drone
    @test !polyroots.docs # Documentation is in the README!
    # We can also use broadcasting!
    @test Set(results) == Set(analyze_from_registry.(packages))

    # check `analyze_from_registry!` directly
    mktempdir() do root
        measurements2 = analyze_from_registry!(root, joinpath(general, "M", "Measurements"))
        @test measurements == measurements2
        @test isdir(joinpath(root, "eff96d63-e80a-5855-80a2-b1b0885c5ab7")) # not cleaned up yet
    end
end

@testset "`analyze`" begin
    pkg = analyze(pkgdir(AnalyzeRegistry))
    @test pkg.repo == "" # can't find repo from source code
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

    # the tests folder isn't a package!
    # But this helps catch issues in error paths for when things go wrong
    bad_pkg = analyze(".")
    @test bad_pkg.repo == ""
    @test bad_pkg.uuid == UUID(UInt128(0))
    @test !bad_pkg.cirrus
    @test isempty(bad_pkg.license_files)
    @test isempty(bad_pkg.licenses_in_project)
end

@testset "`subdir` support" begin
    snoop_path = only(find_packages("SnoopCompileCore"))
    snoop = analyze_from_registry(snoop_path)
    @test !isempty(snoop.subdir)
    @test snoop.name == "SnoopCompileCore" # this test would fail if we were parsing the wrong Project.toml (that of SnoopCompile)
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
    this_project = (; name = "AnalyzeRegistry", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project = String[])
    @test parse_project(joinpath(@__DIR__, "..")) == this_project

    # has `license = "MIT"`
    project_1 = (; name = "AnalyzeRegistry", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project=["MIT"])
    @test parse_project("license_in_project") == project_1

    # has `license = ["MIT", "GPL"]`
    project_2 = (; name = "AnalyzeRegistry", uuid = UUID("e713c705-17e4-4cec-abe0-95bf5bf3e10c"), licenses_in_project=["MIT", "GPL"])
    @test parse_project("licenses_in_project") == project_2
end

@testset "`show`" begin
    # this is mostly to test that `show` doesn't error
    str = sprint(show, analyze(pkgdir(AnalyzeRegistry)))
    @test occursin("* uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c", str)
    @test occursin("* OSI approved: true", str)
end
