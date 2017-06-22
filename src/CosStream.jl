export decode

const Filter_ASCIIHexDecode=CosName("ASCIIHexDecode")
const Filter_ASCII85Decode=CosName("ASCII85Decode")
const Filter_LZWDecode=CosName("LZWDecode")
const Filter_FlateDecode=CosName("FlateDecode")
const Filter_RunLengthDecode=CosName("RunLengthDecode")
const Filter_CCITTFaxDecode=CosName("CCITTFaxDecode")
const Filter_JBIG2Decode=CosName("JBIG2Decode")
const Filter_DCTDecode=CosName("DCTDecode")
const Filter_JPXDecode=CosName("JPXDecode")
const Filter_Crypt=CosName("Crypt")

function _not_implemented(input)
  error(E_NOT_IMPLEMENTED)
end

using Libz

"""
Decodes using the LZWDecode compression
"""
function decode_lzw(stm::CosStream)
  print("Ready to decode the LZW stream")
end

function decode_flate(input)
  return ZlibInflateInputStream(input; gzip=false)
end

using BufferedStreams

function decode_asciihex(input)
  return decode_asciihex(BufferedInputStream(input))
end

function decode_ascii85(input)
  return decode_ascii85(BufferedInputStream(input))
end

function decode_rle(input)
  return decode_rle(BufferedInputStream(input))
end

const function_map = Dict(
   Filter_ASCIIHexDecode => decode_asciihex,
   Filter_ASCII85Decode => decode_ascii85,
   Filter_LZWDecode => _not_implemented,
   Filter_FlateDecode => decode_flate,
   Filter_RunLengthDecode => decode_rle,
   Filter_CCITTFaxDecode => _not_implemented,
   Filter_JBIG2Decode => _not_implemented,
   Filter_DCTDecode => _not_implemented,
   Filter_JPXDecode => _not_implemented,
   Filter_Crypt => _not_implemented
)


""""
Reads the filter data and decodes the stream.
"""
function decode(stm::CosObject)

  filename = get(stm, CosStream_F)
  filters = get(stm, CosStream_FFilter)

  io = open(filename |> get, "r")

  return decode_filter(io, filters)
end

function decode_filter(io, filter::CosName)
  return (io |> function_map[filter])
end

function decode_filter(io, filters::CosArray)
  bufstm = io
  for filter in filters
    bufstm = decode_filter(bufstm, filter)
  end
  return bufstm
end

type RLEDecodeSource{T<:BufferedInputStream}
  input::T
  run::Array{UInt8,1}
  s::UInt8
  e::UInt8
  isResidue::Bool
  isEOD::Bool

end

function RLEDecodeSource(input::T) where {T<:BufferedInputStream}
  return RLEDecodeSource(input, zeros(run, UInt8, (128,)), 0x00, 0x00, false, false)
end

function eof(source::RLEDecodeSource)
  return source.isEOD && eof(source.input)
end

function BufferedStreams.readbytes!(
        source::RLEDecodeSource,
        buffer::Vector{UInt8},
        from::Int, to::Int)
  count = 0
  while((from <= to) && !eof(source))
    if (source.isResidue)
      nbres = source.e - source.s + 1
      nbbuf = to - from + 1
      isResidue = (nbres > nbbuf)
      nbcpy = isResidue? nbbuf : nbres
      copy!(buffer, from, source.run, source.s, nbcpy)

      count = count + nbcpy

      source.s = isResidue? 0: (source.s + nbcpy)
      source.e = isResidue? 0: source.e
      source.isResidue = isResidue

      if (nbres >= nbbuf)
        return nbbuf
      end

      from = from + nbcpy
    else
      load_rle_input!(source)
    end
  end
end

function load_rle_input!(source::RLEDecodeSource)
  if (source.isResidue || eof(source.input))
    return source
  end

  lb::UInt8[1]
  readbytes!(source.input, lb, 1, 1)

  source.e = 0
  if (lb[1] == 128)
    source.isEOD = true
    return source
  elseif (lb[1] < 128)
    nb = readbytes!(source.input, source.run, 1, lb[1]+1)
    source.e = nb
  else
    if (!eof(source.input))
      c::UInt8[1]
      readbytes!(source.input, c, 1, 1)
      fill!(source.run, c[1])
      source.e = 257 - lb[1]
    end
  end
  source.s = 1
  source.isResidue = true
  return source
end



function decode_rle(input::BufferedInputStream)
  return BufferedInputStream(RLEDecodeSource(input))
end

type ASCIIHexDecodeSource{T<:BufferedInputStream}
  input::T
end

function BufferedStreams.readbytes!(
        source::ASCIIHexDecodeSource,
        buffer::Vector{UInt8},
        from::Int, to::Int)
  nbneeded = to - from + 1
  nbread   = nbneeded*2
  data::Array{UInt,1}

  ndata = readbytes!(source.input, data, 1, nbread)
  if (ndata < nbread)
    if (rem(ndata,2)==1)
      ndata = ndata + 1
      data[ndata] = DIGIT_ZERO
    end
  end
  nbreturn = ndata / 2

  i = j = 0
  while i < nbreturn
    n = 0
    c = data[i+=1]
    n = DIGIT_ZERO    <= c <= DIGIT_NINE    ? c - DIGIT_ZERO :
        LATIN_A       <= c <= LATIN_F       ? c - LATIN_A + 10 :
        LATIN_UPPER_A <= c <= LATIN_UPPER_F ? c - LATIN_UPPER_A + 10 : error("Input string isn't a hexadecimal string")
    c = data[i+=1]
    n = DIGIT_ZERO    <= c <= DIGIT_NINE    ? n << 4 + c - DIGIT_ZERO :
        LATIN_A       <= c <= LATIN_F       ? n << 4 + c - LATIN_A + 10 :
        LATIN_UPPER_A <= c <= LATIN_UPPER_F ? n << 4 + c - LATIN_UPPER_A + 10 : error("Input string isn't a hexadecimal string")
    buffer[j+=1] = n
  end
  return nbreturn
end

function decode_asciihex(input::BufferedInputStream)
  return BufferedInputStream(ASCIIHexDecodeSource(input))
end

#This is still buggy. Needs to be worked upon. 

type ASCII85DecodeSource{T<:BufferedInputStream}
  input::T
  residue::Array{UInt8,1}
end

function BufferedStreams.readbytes!(
        source::ASCII85DecodeSource,
        buffer::Vector{UInt8},
        from::Int, to::Int)
  nbneeded = to - from + 1
  reslen = length(source.residue)

  if (reslen >= nbneeded)
    copy!(buffer, from, source.residue, 1, nbneeded)
    splice!(source.residue, 1:nbneeded)
    return nbneeded
  else
    copy!(buffer, from, source.residue, 1, reslen)
    splice!(source.residue, 1:reslen)
    nbneeded = nbneeded - reslen
    from = from + reslen
  end
  nbneeded = to - from + 1
  nbneeded = (nbneeded + 3)/4*4

  nbread   = nbneeded/4*5

  data::Array{UInt,1}

  ndata = readbytes!(source.input, data, 1, nbread)

  count = 0
  iter = 0
  while (count < nbneeded) || (iter < ndata)
    n::UInt32 = 0
    b1 = ((iter+=1) < ndata)? data[iter]:BANG
    if (b1 == LATIN_Z)
      n = 0
    else
      n = (b1-BANG)*85
      b2 = ((iter+=1) < ndata)? data[iter]:BANG
      n += (b2-BANG)
      b3 = ((iter+=1) < ndata)? data[iter]:BANG
      n *= 85
      n += (b3-BANG)
      b4 = ((iter+=1) < ndata)? data[iter]:BANG
      n *= 85
      n += (b4-BANG)
      b5 = ((iter+=1) < ndata)? data[iter]:BANG
      n *= 85
      n += (b5-BANG)
    end
    arr = reinterpret(UInt8[4], n)
    if (from+4 <= to)
      copy!(buffer, from, arr, 1, 4)
      from += 4
      count += 4
    else
      copy!(buffer, from, arr, 1, to - from + 1)
      from = to + 1
      count += (to - from +1)
      rest = 4 - (to - from +1)
      copy!(source.residue, 1, arr, to-from+2, rest)
    end
  end
  return count + reslen
end



function decode_ascii85(input::BufferedInputStream)
  return BufferedInputStream(ASCII85DecodeSource(input))
end
