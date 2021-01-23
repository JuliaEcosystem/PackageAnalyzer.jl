using Test

using AnalyzeRegistry

@testset "AnalyzeRegistry" begin
    general = general_registry()
    @test isdir(general)
    @test all(isdir, find_packages())
    # Test some properties of the `Measurements` package.  NOTE: they may change
    # in the future!
    measurements = analyze(joinpath(general, "M", "Measurements"))
    @test measurements.reachable
    @test measurements.docs
    @test measurements.runtests
    @test !measurements.buildkite
    # Test results of a couple of packages.  Same caveat as above
    packages = [joinpath(general, p...) for p in (("C", "Cuba"), ("P", "PolynomialRoots"))]
    results = analyze(packages)
    cuba, polyroots = results
    @test length(filter(p -> p.reachable, results)) == 2
    @test length(filter(p -> p.runtests, results)) == 2
    @test cuba.github_actions
    @test !polyroots.docs # Documentation is in the README!
    # We can also use broadcasting!
    @test Set(results) == Set(analyze.(packages))
end
