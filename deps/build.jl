using BinDeps

@BinDeps.setup

if !Sys.iswindows()
    libz = library_dependency("libz")
    provides(AptGet, Dict("zlib" => libz, "zlib1g" => libz))
    provides(Yum, "zlib", [libz])
    provides(Pacman, "zlib", [libz])
else
    using WinRPM
    libz = library_dependency("zlib1")
    provides(WinRPM.RPM, "zlib1", libz, os=:Windows)
end

@BinDeps.install Dict([:libz => :libz])

