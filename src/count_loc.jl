function count_loc(dir)
    all_counted_dirs = String[]
    counts  = cd(dir) do
        docs = count_loc_subdirs!(all_counted_dirs, ["docs", "doc"])
        src = count_loc_subdirs!(all_counted_dirs, ["src"])
        test = count_loc_subdirs!(all_counted_dirs, ["test"])
    
        all_others = try
            JSON3.read(read(`tokei --output json . -e$(all_counted_dirs)`))
        catch e
            @error e
            missing
        end
        (; docs, src, test, all_others)
    end
    return make_loc_table(counts)
end

# counts the lines of code in each existing subdirectory in `subdirs`
# and updates `all_counted_dirs` with the subdirs that were counted.
function count_loc_subdirs!(all_counted_dirs, subdirs)
    filter!(isdir, subdirs)
    isempty(subdirs) && return missing
    append!(all_counted_dirs, ("/"*s for s in subdirs))
    return try
        JSON3.read(read(`tokei --output json $(subdirs)`))
    catch e
        @error e
        missing
    end
end

const LoCTableEltype = @NamedTuple{directory::Symbol, language::Symbol, files::Int, code::Int, comments::Int, blanks::Int}

function make_loc_table(loc)
    table = LoCTableEltype[]
    for (directory, directory_loc) in pairs(loc)
        ismissing(directory_loc) && continue
        for (language, language_loc) in pairs(directory_loc)
            ismissing(language_loc) && continue
            language == :Total && continue
            language_loc.inaccurate && continue
            files = length(language_loc[:reports])
            code = language_loc[:code]
            comments = language_loc[:comments]
            blanks = language_loc[:blanks]
            push!(table, (; directory, language, files, code, comments, blanks))
        end
    end
    return table
end

count_julia_loc(table, dir) = sum(row.code for row in table if row.directory == dir && row.language == :Julia; init=0)
