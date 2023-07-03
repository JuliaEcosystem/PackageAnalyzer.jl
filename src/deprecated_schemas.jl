# These are kept to ensure we can continue to deserialize them

# We use the workaround from <https://github.com/beacon-biosignals/Legolas.jl/issues/95#issuecomment-1586255450>
# to update our nested schemas.

@version LinesOfCodeV1 begin
    directory::String
    language::Symbol
    sublanguage::Union{Nothing, Symbol}
    files::Int
    code::Int
    comments::Int
    blanks::Int
end

# Ensure we allow deserializing `LinesOfCodeV1`'s
Legolas.accepted_field_type(::PackageV1SchemaVersion, ::Type{Vector{LinesOfCodeV2}}) = Union{<:AbstractVector{LinesOfCodeV1}, <:AbstractVector{LinesOfCodeV2}}
