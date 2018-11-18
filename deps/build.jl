using BinDeps

@BinDeps.setup

libz = library_dependency("libz", aliases=["libz", "libzlib", "zlib1"])

if !Sys.iswindows()
    provides(AptGet, Dict("zlib" => libz, "zlib1g" => libz))
    provides(Yum, "zlib", [libz])
    provides(Pacman, "zlib", [libz])	
else
    using WinRPM
    provides(WinRPM.RPM, "zlib1", [libz])
end

@BinDeps.install Dict([:libz => :libz])
