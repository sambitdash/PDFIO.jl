export get_tempdir,
       get_tempfilepath,
       util_open,
       util_close,
       load_data_file,
       dict_remap,
       NativeEncodingToUnicode,
       PDFEncodingToUnicode,
       utilPrintOpenFiles

# Non-exported variable that retains the current tempdir location.
# This shoould be only accessed by get_tempdir() only

CURRENT_TMPDIR=""

"""
On every launch of the application a new directory needs to be created
that will have the path of the new directory.
"""
function get_tempdir()
    global CURRENT_TMPDIR
    if (CURRENT_TMPDIR == "" )||!isdir(CURRENT_TMPDIR)
        CURRENT_TMPDIR= abspath(mktempdir())
    end
    return CURRENT_TMPDIR
end

get_tempfilepath()=mktemp(get_tempdir())
util_open(filename, mode)=open(filename, mode)
util_close(handle::IOStream)=close(handle)
utilPrintOpenFiles()=[]

import Base: zero
zero(::Type{Char}) = Char(0x00)

function load_data_file(filename)
    path = joinpath(Pkg.dir("PDFIO"), "data", filename)
    return readdlm(path, ',', String, '\n')
end

function dict_remap(ab, bc)
    d = Dict()
    for (a, b) in ab
        c = get(bc, b, zero(valtype(bc)))
        d[a] = c
    end
    return d
end

const PDFEncoding_to_Unicode = begin
    d = Dict()
    m = load_data_file("pdf-doc-encoding.txt")
    map(m[:,3], m[:,4]) do x, y
        e = parse(UInt8, x, 8)
        u = (y != "") ? Char(parse(UInt, y, 16)) : Char(e)
        d[e] = u
    end
    d
end

function NativeEncodingToUnicode(barr::Vector{UInt8}, mapping::Dict)
    l = length(barr)
    carr = Vector{Char}(l)
    for i = 1:l
        carr[i] = get(mapping, barr[i], zero(Char))
    end
    return carr
end

PDFEncodingToUnicode(barr::Vector{UInt8}) =
    NativeEncodingToUnicode(barr, PDFEncoding_to_Unicode)
