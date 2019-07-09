# zlib inflate implementation similar to: https://zlib.net/zpipe.c
mutable struct z_stream
    next_in::Ptr{UInt8}
    avail_in::Cuint
    total_in::Culong
    next_out::Ptr{UInt8}
    avail_out::Cuint
    total_out::Culong
    msg::Ptr{UInt8}
    state::Ptr{Cvoid}
    zalloc::Ptr{Cvoid}
    zfree::Ptr{Cvoid}
    opaque::Ptr{Cvoid}
    data_type::Cint
    adler::Culong
    reserved::Culong

    function z_stream()
        new(
            C_NULL,  # next_in
            0,       # avail_in  
            0,       # total_in  
            C_NULL,  # next_out  
            0,       # avail_out 
            0,       # total_out 
            C_NULL,  # msg       
            C_NULL,  # state     
            C_NULL,  # zalloc
            C_NULL,  # zfree     
            C_NULL,  # opaque    
            0,       # data_type 
            0,       # adler     
            0,       # reserved  
        )
    end
end

const Z_OK            = 0
const Z_STREAM_END    = 1
const Z_NEED_DICT     = 2
const Z_ERRNO         = -1
const Z_STREAM_ERROR  = -2
const Z_DATA_ERROR    = -3
const Z_MEM_ERROR     = -4
const Z_BUF_ERROR     = -5
const Z_VERSION_ERROR = -6

@static isfile(joinpath(dirname(@__FILE__),"..","deps","deps.jl")) ||
        error("PDFIO not properly installed. Please run Pkg.build(\"PDFIO\")")

include("../deps/deps.jl")

_zlibVersion() = ccall((:zlibVersion, libz), Ptr{Cstring}, ())

_inflateInit(stm::z_stream) =
    ccall((:inflateInit2_, libz), Cint,
          (Ptr{Cvoid}, Cint, Ptr{Cstring}, Cint),
          Ref(stm), 47, _zlibVersion(), sizeof(z_stream))

_inflateEnd(stm::z_stream) =
    ccall((:inflateEnd, libz), Cint, (Ref{z_stream},), stm)

_inflate(stm::z_stream) =
    ccall((:inflate, libz), Cint, (Ref{z_stream}, Cint), stm, 0)

function inflate(io::IO)
    CHUNK = 16384

    iob = IOBuffer()
    
    strm = z_stream()
    ret = _inflateInit(strm)
    ret != Z_OK && _zerror(ret)

    inb = zeros(UInt8, CHUNK)
    oub = zeros(UInt8, CHUNK)

    try
        while ret != Z_STREAM_END
            strm.avail_in = readbytes!(io, inb, CHUNK)
            strm.avail_in == 0 && break
            strm.next_in = pointer(inb)

            strm.avail_out = 0
            while strm.avail_out == 0
                strm.avail_out = CHUNK
                strm.next_out = pointer(oub)
                ret = _inflate(strm)
                ret == Z_STREAM_ERROR && error("zlib stream state clobbered")
                ret != Z_OK && ret != Z_STREAM_END && _zerror(ret)
                have = CHUNK - strm.avail_out
                resize!(oub, have)
                write(iob, oub)
                resize!(oub, CHUNK)
            end
        end
    finally
        _inflateEnd(strm)
    end
    return seekstart(iob)
end

function _zerror(ret::Cint)
    msg =
        ret == Z_STREAM_ERROR  ? "invalid compression level" :
        ret == Z_DATA_ERROR    ? "invalid or incomplete deflate data" :
        ret == Z_MEM_ERROR     ? "out of memory" :
        ret == Z_VERSION_ERROR ? "zlib version mismatch!" :
                                 "zlib internal error"
    
    error(msg)
end

init_table(size::Int) =
    ([(i <= 256) ? [ UInt8(i-1)] :
      i == 257  ? [ UInt8(0)]   :
      i == 258  ? [ UInt8(0)] : UInt8[] for i = 1:size], 9, 258)
@inline function next_number(bin, cl, sy, si)
    sy -= 1
    si -= 1
    n = 0
    while cl > 0
        @inbounds b::Int = bin[sy + 1]
        m = UInt8(0xff) >> si
        b = b & m
        cl -= (8 - si)
        b <<= cl
        n += b
        si, sy = 0, sy + 1
        1 <= cl <= 7 || continue
        si = cl
        @inbounds b = bin[sy + 1]
        m = UInt8(0xff) << (8 - si)
        b = (b & m) >> (8 - si)
        n += b
        cl = 0
    end
    return n, sy + 1, si + 1
end

function decode_lzw(io::IO, earlyChange::Int = 1)
    bin = read(io)
    util_close(io)
    len = length(bin)
    t, cl, it = init_table(4096)
    hy, hi = 1, 1
    iob = IOBuffer()
    old_set = false
    old, c = 1, 0x0
    s = UInt8[]
    while hy < len && hi <= 8
        n, hy, hi = next_number(bin, cl, hy, hi)
        hy > len && break
        n == 257 && break
        if n == 256
            t, cl, it = init_table(4096)
            old_set = false
        else
            if n < it
                if !old_set 
                    old = n
                    write(iob, t[n+1])
                    c = t[n + 1][1]
                    old_set = true
                    continue
                end
                s = t[n + 1]
            elseif n == it
                s = copy(t[old + 1])
                push!(s, c)
            else
                error(E_FAILED_COMPRESSION*" $n : $it")
            end
            write(iob, s)
            c = s[1]
            append!(t[it+1], t[old+1])
            push!(t[it+1], c)
            old = n
            it == 4095 && continue
            if it == ((1 << cl) - 1 - earlyChange)
                cl += 1
            end
            it += 1
        end
    end
    return seekstart(iob)
end
