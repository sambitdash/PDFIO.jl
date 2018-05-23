# zlib inflate implementation similar to: https://zlib.net/zpipe.c
mutable struct z_stream
    next_in::Ptr{UInt8}
    avail_in::Cuint
    total_in::Culong
    next_out::Ptr{UInt8}
    avail_out::Cuint
    total_out::Culong
    msg::Ptr{UInt8}
    state::Ptr{Void}
    zalloc::Ptr{Void}
    zfree::Ptr{Void}
    opaque::Ptr{Void}
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

if is_windows()
    const libz = "zlib1"
else
    const libz = "libz"
end

_zlibVersion() = ccall((:zlibVersion, libz), Ptr{UInt8}, ())

_inflateInit(stm::z_stream) =
    ccall((:inflateInit2_, libz), Cint, (Ptr{z_stream}, Cint, Ptr{UInt8}, Cint),
          &stm, 47, _zlibVersion(), sizeof(z_stream))

_inflateEnd(stm::z_stream) =
    ccall((:inflateEnd, libz), Cint, (Ptr{z_stream},), &stm)

_inflate(stm::z_stream) =
    ccall((:inflate, libz), Cint, (Ptr{z_stream}, Cint), &stm, 0)

function inflate(io::IO)
    CHUNK = 16384

    iob = IOBuffer()
    
    strm = z_stream()
    ret = _inflateInit(strm)
    ret != Z_OK && _zerror(ret)

    inb = Vector{UInt8}(CHUNK)
    oub = Vector{UInt8}(CHUNK)

    while ret != Z_STREAM_END
        strm.avail_in = readbytes!(io, inb, CHUNK)
        strm.avail_in == 0 && break
        strm.next_in = pointer(inb)

        strm.avail_out = 0
        while strm.avail_out == 0
            strm.avail_out = CHUNK
            strm.next_out = pointer(oub)
            ret = _inflate(strm)
            @assert ret != Z_STREAM_ERROR  "zlib stream state clobbered"
            if ret != Z_OK 
                _inflateEnd(strm)
                ret != Z_STREAM_END && _zerror(ret)
            end
            have = CHUNK - strm.avail_out
            resize!(oub, have)
            write(iob, oub)
            resize!(oub, CHUNK)
        end
    end
    _inflateEnd(strm)
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
