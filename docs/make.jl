using Workbench
using Documenter

DocMeta.setdocmeta!(Workbench, :DocTestSetup, :(using Workbench); recursive=true)

makedocs(;
    modules=[Workbench],
    authors="Matt Helm <mthelm85@gmail.com> and contributors",
    sitename="Workbench.jl",
    format=Documenter.HTML(;
        canonical="https://mthelm85.github.io/Workbench.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mthelm85/Workbench.jl",
    devbranch="master",
)
