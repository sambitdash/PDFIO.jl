
if Base.HOME_PROJECT[] !== nothing
    # JuliaLang/julia/pull/28625
    Base.HOME_PROJECT[] = abspath(Base.HOME_PROJECT[])
end

using Documenter, PDFIO

makedocs(
    format = Documenter.HTML(),
    modules = [PDFIO],
    sitename = "PDFIO",
    pages = [
        "README.md",
        "Architecture and Design" => "arch.md",
        "Encryption in PDF" => "encrypt.md",
        "Digital Signatures" => "digsig.md",
        "API Reference" => "index.md",
        "PDFIO License" => "LICENSE.md"
    ]
)

deploydocs(
    repo   = "github.com/sambitdash/PDFIO.jl.git",
)
