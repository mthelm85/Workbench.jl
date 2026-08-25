using Workbench
using Documenter
using MaterialDocs

DocMeta.setdocmeta!(Workbench, :DocTestSetup, :(using Workbench); recursive=true)

makedocs(;
    modules=[Workbench],
    authors="Matt Helm <mthelm85@gmail.com> and contributors",
    sitename="",
    format=Material3(dark_mode = :light, logo="assets/logo-dark.svg"),
    pages=[
        "Home" => "index.md",
    ],
    warnonly=[:missing_docs],
)

deploydocs(;
    repo="github.com/mthelm85/Workbench.jl",
    devbranch="main",
)
