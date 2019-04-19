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
        "API Structure and Design" => "index.md"
    ]
)

deploydocs(
    repo   = "github.com/sambitdash/PDFIO.jl.git",
)
