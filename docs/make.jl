push!(LOAD_PATH,"../src/")

using Documenter, PDFIO

makedocs(
    format = Documenter.HTML(),
    sitename = "PDFIO",
    pages = [
        "intro.md",
        "API Structure and Design" => "index.md"
    ]
)

deploydocs(
    repo   = "github.com/sambitdash/PDFIO.jl.git",
    target = "build",
    branch = "gh-pages",
    julia  = "1.0",
    deps   = nothing,
    make   = nothing
)
