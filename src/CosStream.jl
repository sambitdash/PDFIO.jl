import Base: eof

export  cosStreamRemoveFilters,
        decode

_not_implemented(input, params) = error(E_NOT_IMPLEMENTED)

include("Inflate.jl")

#=
Decodes using the LZWDecode compression
=#
function decode_lzw(input, parms)
    early = 1
    if parms !== CosNull 
        earlyChange = get(parms, cn"EarlyChange")
        early = earlyChange === CosNull ? 1 : get(earlyChange)
    end
    io = decode_lzw(input, early)
    return apply_flate_params(io, parms)
end

function decode_flate(input, parms)
    io = inflate(input)
    util_close(input)
    return apply_flate_params(io, parms)
end

apply_flate_params(input, parms) = input

decode_asciihex(input::IO, parms) = decode_asciihex(input)

decode_ascii85(input::IO, parms) = decode_ascii85(input)

decode_rle(input::IO, parms) = decode_rle(input)

decode_jpg(input::IO, parms) = decode_jpg(input) = input

decode_jpx(input::IO, parms) = decode_jpx(input) = input

const function_map = Dict(
                          cn"ASCIIHexDecode" => decode_asciihex,
                          cn"ASCII85Decode" => decode_ascii85,
                          cn"LZWDecode" => decode_lzw,
                          cn"FlateDecode" => decode_flate,
                          cn"RunLengthDecode" => decode_rle,
                          cn"CCITTFaxDecode" => _not_implemented,
                          cn"JBIG2Decode" => _not_implemented,
                          cn"DCTDecode" => decode_jpg,
                          cn"JPXDecode" => decode_jpx,
                          cn"Crypt" => _not_implemented
                         )

function cosStreamRemoveFilters(stm::IDD{CosStream}, until=-1)
    filters = get(stm, cn"FFilter")
    if (filters != CosNull)
        bufstm = decode(stm, until)
        data = read(bufstm)
        util_close(bufstm)
        filename = get(stm, cn"F") |> get |> CDTextString
        n = write(filename, data)
        if until == -1
            set!(stm, cn"FFilter", CosNull)
            set!(stm, cn"FDecodeParms", CosNull)
        else
            filters = get(stm, cn"FFilter")
            parms   = get(stm, cn"FDecodeParms")
            l = length(filters)
            if l == until
                set!(stm, cn"FFilter", CosNull)
                set!(stm, cn"FDecodeParms", CosNull)
            else
                deleteat!(filters, 1:until)
                parms !== CosNull && deleteat!(parms, 1:until)
            end
        end
        set!(stm, cn"Length", CosInt(n))
    end
    return stm
end


# Reads the filter data and decodes the stream.
function decode(stm::IDD{CosStream}, until = -1)
    filename = get(stm, cn"F")
    filters =  get(stm, cn"FFilter")
    parms =    get(stm, cn"FDecodeParms")

    io = util_open(String(filename), "r")

    return decode_filter(io, filters, parms, until)
end

decode_filter(io::IO, filter::CosNullType, parms::CosObject, until=-1) = io

decode_filter(io::IO, filter::CosName, parms::CosObject, until=-1) =
    function_map[filter](io, parms)

function decode_filter(io::IO, filters::CosArray, parms::IDDN{CosArray},
                       until::Int=length(filters))
    until == -1 && (until = length(filters))
    bufstm = io
    vf, vp = get(filters), (parms === CosNull ? CosNull : get(parms))
    for i = 1:until
        f, p = vf[i], (vp === CosNull ? CosNull : vp[i])
        bufstm = decode_filter(bufstm, f, p)
    end
    return bufstm
end

function apply_flate_params(input::IO, parms::CosDict)
    predictor        = get(parms, cn"Predictor")
    colors           = get(parms, cn"Colors")
    bitspercomponent = get(parms, cn"BitsPerComponent")
    columns          = get(parms, cn"Columns")

    predictor_n        = (predictor !== CosNull) ? get(predictor) : 0
    colors_n           = (colors !== CosNull) ?    get(colors) : 0
    bitspercomponent_n = (bitspercomponent !== CosNull) ?
                              get(bitspercomponent) : 0
    columns_n          = (columns !== CosNull) ? get(columns) : 0

    return (predictor_n == 2)  ? error(E_NOT_IMPLEMENTED) :
           (predictor_n >= 10) ? apply_flate_params(input, predictor_n - 10,
                                                    columns_n) : input
end


# Exactly as stated in https://www.w3.org/TR/PNG-Filters.html
@inline function PaethPredictor(a, b, c)
    # a = left, b = above, c = upper left
    p = a + b - c        # initial estimate
    pa = abs(p - a)      # distances to a, b, c
    pb = abs(p - b)
    pc = abs(p - c)
    # return nearest of a,b,c,
    # breaking ties in order a,b,c.
    return  (pa <= pb && pa <= pc) ? a :
                        (pb <= pc) ? b :
                                     c
end

@inline function png_predictor_rule(curr, prev, n, row, rule)
    if rule == 0
        copyto!(curr, 1, row, 2, n)
    elseif rule == 1
        curr[1] = row[2]
        for i=2:n
            curr[i] = curr[i-1] + row[i+1]
        end
    elseif rule == 2
        for i=1:n
            curr[i] = prev[i] + row[i+1]
        end
    elseif rule == 3
        curr[1] = prev[1] + row[2]
        for i=2:n
            avg = div(curr[i-1] + prev[i], 2)
            curr[i] = avg + row[i+1]
        end
    elseif (rule == 4)
        curr[1] = prev[1] + row[2]
        for i=2:n
            pred = PaethPredictor(curr[i-1], prev[i], prev[i-1])
            curr[i] = pred + row[i+1]
        end
    end
end

function apply_flate_params(io::IO, pred::Int, col::Int)
    iob = IOBuffer()
    incol = col + 1
    curr = zeros(UInt8, col)
    prev = zeros(UInt8, col)
    nline = 0
    while !eof(io)
        row = read(io, incol)
        @assert (pred != 5) && (row[1] == pred)
        nline >= 1 && copyto!(prev, curr)
        png_predictor_rule(curr, prev, col, row, row[1])
        write(iob, curr)
        nline += 1
    end
    util_close(io)
    return seekstart(iob)
end

function decode_rle(input::IO)
    iob = IOBuffer()
    b = read(input, UInt8)
    a = Vector{UInt8}(undef, 256)
    while !eof(input)
        b == 0x80 && break
        if b < 0x80
            resize!(a, b + 1)
            nb = readbytes!(input, a, b + 1)
            resize!(a, nb)
            write(iob, a)
        else
            c = read(input, UInt8)
            write(iob, fill(c, 257 - b))
        end
        b = read(input, UInt8)
    end
    util_close(input)
    return seekstart(iob)
end

# This function is very tolerant as a hex2bytes converter
# It rejects any bytes less than '0' so that control characters
# are ignored. Any character above '9' it sanitizes to a number
# under 0xF. PDF Spec also does not mandate the stream to have
# even number of values. If odd number of hexits are given '0'
# has to be appended to th end.

function decode_asciihex(input::IO)
    data = read(input)
    nb = length(data)
    B0 = UInt8('0')
    B9 = UInt8('9')
    j = 0
    k = true
    for i = 1:nb
        @inbounds b = data[i]
        b < B0 && continue
        c = b > B9 ? ((b & 0x07) + 0x09) : (b & 0x0F)
        if k 
            data[j+=1] = c << 4
        else
            data[j] += c
        end
        k = !k
    end
    util_close(input)
    resize!(data, j)
    return IOBuffer(data)
end

function _extend_buffer!(data, nb, i, j)
    SLIDE = 1024
    if j + 4 > i
        resize!(data, nb + SLIDE)
        copyto!(data, i + 1 + SLIDE, data, i + 1, nb - i)
        nb += SLIDE
         i += SLIDE
    end
    return nb, i
end

function decode_ascii85(input::IO)
    data = read(input)
    nb = length(data)
    i = j = k = 0
    n::UInt32 = 0
    while i < nb
        b = data[i+=1]
        if b == LATIN_Z
            k > 0 && error(E_UNEXPECTED_CHAR)
            nb, i = _extend_buffer!(data, nb, i, j)
            for ii=1:4
                data[j+=1] = 0x0
            end
        elseif b == TILDE
            c = data[i+=1]
            i <= nb && c == GREATER_THAN && break
        elseif ispdfspace(b)
            k = 0
            n = 0
        elseif BANG <= b <= LATIN_U
            v = b - BANG
            n *= 85
            n += v
            k = k == 4 ? 0 : (k + 1)
            if k == 0
                for l=4:-1:1
                    data[j+l] = UInt8(n & 0xff)
                    n >>= 8
                end
                j += 4
                n = 0
            end
        else
            error(E_UNEXPECTED_CHAR)
        end
    end
    if k > 0
        for kk = k:4
            n *= 85
        end
        for l=4:-1:1
            l <= k && (data[j+l] = UInt8(n & 0xff))
            n >>= 8
        end
        j += (k - 1)
    end
    util_close(input)
    resize!(data, j)
    return IOBuffer(data)
end
