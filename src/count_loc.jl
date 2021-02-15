function count_loc(dir)
    # we `cd` so that we get relative paths in the `tokei` output.
    # This makes it easy to process later, since we have uniform filepaths
    json = cd(dir) do
        try
            # local tokei for now:
            # tokei() do exe
            JSON3.read(read(`tokei --output json .`))
            # end
        catch e
            @error e
            missing
        end
    end
    return make_loc_table(json)
end


const LoCTableEltype = @NamedTuple{directory::String, language::Symbol, sublanguage::Union{Nothing, Symbol}, files::Int, code::Int, comments::Int, blanks::Int}

function make_loc_table(json)
    table = LoCTableEltype[]
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
            push!(table, (; directory, language, sublanguage, count.files, count.code, count.comments, count.blanks))
        end
    end
    return table
end

function loc_update!(d, key, new)
    prev = get!(d, key, (; files=0, code=0, comments=0, blanks=0))
    d[key] = (; files = prev.files + 1, code = prev.code + new.code, comments = prev.comments + new.comments, blanks = prev.blanks + new.blanks )
end

count_julia_loc(table, dir) = sum(row.code for row in table if row.directory == dir && row.language == :Julia; init=0)
