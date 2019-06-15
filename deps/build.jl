using BinDeps

@BinDeps.setup

using Libdl

function validate_libz_version(name, handle)
    f = Libdl.dlsym_e(handle, "zlibVersion")
    f == C_NULL && return false
    ver = VersionNumber(unsafe_string(ccall(f, Cstring, ())))
    println("Version Libz is: $ver")
    # Version 1.2.8 or above
    return ver >= v"1.2.8"
end

function validate_openssl_version(name, handle)
    f = Libdl.dlsym_e(handle, "OpenSSL_version_num")
    f == C_NULL && return false
    v = ccall(f, Culong, ())
    println("Version OpenSSL is: $v")
    # Version 1.0.2f or above
    return v >= 0x1000200f
end

libz = library_dependency("libz", aliases=["libz", "libzlib", "zlib1"], validate=validate_libz_version)
libcrypto = library_dependency("libcrypto", aliases=["libcrypto"]) #validate=validate_openssl_version)

if !Sys.iswindows()
    provides(AptGet, Dict("zlib" => libz, "zlib1g" => libz))
    provides(Yum, "zlib", [libz])
    provides(Pacman, "zlib", [libz])
    provides(AptGet, Dict("libssl-dev" => libcrypto))
    provides(Yum, "openssl-libs", [libcrypto])
    provides(Pacman, "openssl", [libcrypto])	
else
    using WinRPM
    provides(WinRPM.RPM, "zlib1", [libz])
    provides(WinRPM.RPM, "libopenssl", [libcrypto])
end

@BinDeps.install Dict([:libz => :libz, :libcrypto => :libcrypto])
