using BinDeps

@BinDeps.setup()

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
    println("Version OpenSSL is: $(string(v, base=16))")
    # Version 1.1.0f or above
    return v >= 0x1010000f
end

libz = library_dependency("libz", aliases=["libz", "libzlib", "zlib1"], validate=validate_libz_version)
libcrypto = library_dependency("libcrypto", aliases=["libcrypto"], validate=validate_openssl_version)

prefix = joinpath(@__DIR__, "usr")

if !Sys.iswindows()
    provides(Sources,
             URI("https://github.com/madler/zlib/archive/v1.2.11.tar.gz"),
             libz, unpacked_dir="zlib-1.2.11")
    provides(SimpleBuild,
             (@build_steps begin
                 GetSources(libz)
                 @build_steps begin
                     ChangeDirectory(joinpath(BinDeps.depsdir(libz), "src", "zlib-1.2.11"))
                     `./configure --prefix=$prefix`
                     `make`
                     `make install`
                 end
              end), libz, os = :Unix)

    provides(Sources,
             URI("https://github.com/openssl/openssl/archive/OpenSSL_1_1_0k.tar.gz"),
             libcrypto, unpacked_dir="openssl-OpenSSL_1_1_0k")
    provides(SimpleBuild,
             (@build_steps begin
                 GetSources(libcrypto)
                 @build_steps begin
                     ChangeDirectory(joinpath(BinDeps.depsdir(libcrypto), "src", "openssl-OpenSSL_1_1_0k"))
                     `./config --prefix=$prefix`
                     `make depend`
                     `make install`
                 end
              end), libcrypto, os = :Unix)

else
    using WinRPM
    provides(WinRPM.RPM, "zlib1", [libz])
    provides(Sources,
             URI("https://github.com/openssl/openssl/archive/OpenSSL_1_1_0k.zip"),
             libcrypto, unpacked_dir="openssl-OpenSSL_1_1_0k")
    provides(SimpleBuild,
             (@build_steps begin
                 GetSources(libcrypto)
                 @build_steps begin
                     ChangeDirectory(joinpath(BinDeps.depsdir(libcrypto), "src", "openssl-OpenSSL_1_1_0k"))
                     `./config --prefix=$prefix`
                     `make depend`
                     `make install`
                 end
              end), libcrypto, os = :Windows)

end

@BinDeps.install Dict([:libz => :libz, :libcrypto => :libcrypto])
