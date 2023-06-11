# These are kept to ensure we can continue to deserialize them

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
