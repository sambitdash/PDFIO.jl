push!(LOAD_PATH,"../src/")

using Documenter, PDFIO

makedocs(
    format = :html,
    sitename = "PDFIO",
    pages = [
        "intro.md",
        "API Structure and Design" => "index.md"
    ]
)

deploydocs(
    repo   = "github.com/sambitdash/PDFIO.jl.git",
    target = "build",
    deps   = nothing,
    make   = nothing
)
