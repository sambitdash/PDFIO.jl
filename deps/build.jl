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
    # Version 1.1.0 or above
    return v >= 0x1010000f
end

libz = library_dependency("libz", aliases=["libz", "libzlib", "zlib1"], validate=validate_libz_version)
libcrypto = library_dependency("libcrypto", aliases=["libcrypto", "libcrypto-1_1-x64", "libcrypto-1_1"], validate=validate_openssl_version)

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

    osslver = "1_1_0k"
    osslfn  = "OpenSSL_$(osslver)"
    ossldir = "openssl-$(osslfn)"
    osslpkg = "$(osslfn).tar.gz"
    
    provides(Sources,
             URI("https://github.com/openssl/openssl/archive/$(osslpkg)"),
             libcrypto, unpacked_dir="$(ossldir)")
    provides(SimpleBuild,
             (@build_steps begin
                 GetSources(libcrypto)
                 @build_steps begin
                     ChangeDirectory(joinpath(BinDeps.depsdir(libcrypto), "src", "$(ossldir)"))
                     `./config --prefix=$prefix`
                     `make depend`
                     `make install`
                 end
              end), libcrypto, os = :Unix)

else
    zlib_bn  = "zlib-1.2.11-win$(Sys.WORD_SIZE)-mingw"
    zlib_fn  = "$(zlib_bn).zip"
    zlib_uri = "https://bintray.com/vszakats/generic/download_file?file_path=$(zlib_fn)"
    provides(Binaries, URI(zlib_uri), libz, filename="$(zlib_fn)", unpacked_dir="$(zlib_bn)")

    openssl_bn   = "openssl-1.1.0i-win$(Sys.WORD_SIZE)-mingw"
    openssl_fn   = "$(openssl_bn).zip"
    openssl_uri  = "https://bintray.com/vszakats/generic/download_file?file_path=$(openssl_fn)"
    provides(Binaries, URI(openssl_uri), libcrypto, filename="$(openssl_fn)", unpacked_dir="$(openssl_bn)")
end

@BinDeps.install Dict([:libz => :libz, :libcrypto => :libcrypto])
