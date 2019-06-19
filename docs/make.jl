
if Base.HOME_PROJECT[] !== nothing
    # JuliaLang/julia/pull/28625
    Base.HOME_PROJECT[] = abspath(Base.HOME_PROJECT[])
end

using Documenter, PDFIO

makedocs(
    format = Documenter.HTML(),
    sitename = "PDFIO",
    pages = [
        "intro.md",
        "Architecture and Design" => "arch.md",
        "Digital Signatures" => "digsig.md",
        "API Reference" => "index.md"
    ]
)

deploydocs(
    repo   = "github.com/sambitdash/PDFIO.jl.git",
)
