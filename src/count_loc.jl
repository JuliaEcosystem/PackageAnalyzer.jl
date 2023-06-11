function count_loc(dir)
    # we pass `dir` to the command object so that we get relative paths in the `tokei` output.
    # This makes it easy to process later, since we have uniform filepaths
    json = try
        JSON3.read(read(Cmd(`$(tokei()) --output json .`; dir)))
    catch e
        @error "`tokei` error: " exception=e maxlog=2
        missing
    end
    return make_loc_table(json)
end

function make_loc_table(json)
    table = LinesOfCodeV1[]
    ismissing(json) && return table
    for (language, language_loc) in pairs(json)
        # we want to count lines of code per toplevel directory, per language, and per sublanguage (e.g. for Julia inside of Markdown)
        counts = Dict{@NamedTuple{directory::String, sublanguage::Union{Nothing, Symbol}}, @NamedTuple{files::Int, code::Int, comments::Int, blanks::Int}}()
        language == :Total && continue # skip the fake `Total` language
        language_loc.inaccurate && continue # skip if it's marked `inaccurate` (not sure when that happens?)
        for report in language_loc.reports
            # `splitpath(relative_path)[1] == ".", so `splitpath(relative_path)[2]` gives us the toplevel directory or filename
            directory = splitpath(report.name)[2]
            loc_update!(counts, (; directory, sublanguage=nothing), report.stats)
            for (sublanguage, sublanguage_loc) in report.stats.blobs
                loc_update!(counts,  (; directory, sublanguage), sublanguage_loc)
            end
        end
        for ((directory, sublanguage), count) in pairs(counts)
            push!(table, LinesOfCodeV1(; directory, language, sublanguage, count.files, count.code, count.comments, count.blanks))
        end
    end
    d_count = counts_by_col(table, :directory)
    l_count = counts_by_col(table, :language)
    sl_count = counts_by_col(table, :sublanguage)
    sort!(table, by = row->(d_count[row.directory], l_count[row.language], sl_count[row.sublanguage]), rev=true)
    return table
end

function counts_by_col(table, col)
    vals = unique(getproperty(row, col) for row in table)
    return Dict(val => sum(row.code for row in table if getproperty(row, col) == val) for val in vals)
end

function loc_update!(d, key, new)
    prev = get!(d, key, (; files=0, code=0, comments=0, blanks=0))
    d[key] = (; files = prev.files + 1, code = prev.code + new.code, comments = prev.comments + new.comments, blanks = prev.blanks + new.blanks )
end


#####
##### Counting helpers
#####

count_commits(table) = sum(row.contributions for row in table; init=0)
count_commits(pkg::PackageV1) = count_commits(pkg.contributors)

count_contributors(table; type="User") = count(row.type == type for row in table)
count_contributors(pkg::PackageV1; kwargs...) = count_contributors(pkg.contributors; kwargs...)


count_julia_loc(table, dir) = sum(row.code for row in table if row.directory == dir && row.language == :Julia; init=0)

function count_docs(table, dirs=("docs", "doc"))
    rm_langs = (:TOML, :SVG, :CSS, :Javascript)
    sum(row.code + row.comments for row in table if lowercase(row.directory) in dirs && row.language ∉ rm_langs && row.sublanguage ∉ rm_langs; init=0)
end

count_readme(table) = count_docs(table, ("readme", "readme.md"))

count_julia_loc(pkg::PackageV1, args...) = count_julia_loc(pkg.lines_of_code, args...)
count_docs(pkg::PackageV1, args...) = count_docs(pkg.lines_of_code, args...)
count_readme(pkg::PackageV1, args...) = count_readme(pkg.lines_of_code, args...)
