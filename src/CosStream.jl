import Base:eof,close

import Libz:BufferedStreams.readbytes!

import BufferedStreams:readbytes!

export cosStreamRemoveFilters,
       decode

function _not_implemented(input)
  error(E_NOT_IMPLEMENTED)
end

using Libz

using BufferedStreams

"""
Decodes using the LZWDecode compression
"""
function decode_lzw(stm::CosStream)
  println("Ready to decode the LZW stream")
end

function decode_flate(input, parms)
  deflate = ZlibInflateInputStream(input; gzip=false)
  return apply_flate_params(deflate, parms)
end

apply_flate_params(input,parms)=input

using BufferedStreams

function decode_asciihex(input, parms)
  println("decode_asciihex(input,parms)")
  return decode_asciihex(BufferedInputStream(input))
end

function decode_asciihex(input::BufferedInputStream, parms)
  return decode_asciihex(input)
end

function decode_ascii85(input, parms)
  return decode_ascii85(BufferedInputStream(input))
end

function decode_ascii85(input::BufferedInputStream, parms)
  return decode_ascii85(input)
end

function decode_rle(input, parms)
  return decode_rle(BufferedInputStream(input))
end

function decode_rle(input::BufferedInputStream, parms)
  return decode_rle(input)
end

const function_map = Dict(
   CosName("ASCIIHexDecode") => decode_asciihex,
   CosName("ASCII85Decode") => decode_ascii85,
   CosName("LZWDecode") => _not_implemented,
   CosName("FlateDecode") => decode_flate,
   CosName("RunLengthDecode") => decode_rle,
   CosName("CCITTFaxDecode") => _not_implemented,
   CosName("JBIG2Decode") => _not_implemented,
   CosName("DCTDecode") => _not_implemented,
   CosName("JPXDecode") => _not_implemented,
   CosName("Crypt") => _not_implemented
)

function cosStreamRemoveFilters(stm::CosObject)
  filters = get(stm, CosName("FFilter"))

  if (filters != CosNull)
    bufstm = decode(stm)
    data = read(bufstm)
    close(bufstm)
    filename = get(stm, CosName("F"))
    write(filename |> get |> String, data)
    set!(stm, CosName("FFilter"),CosNull)
  end
  return stm
end

"""
Reads the filter data and decodes the stream.
"""
function decode(stm::CosObject)

  filename = get(stm, CosName("F"))
  filters = get(stm, CosName("FFilter"))
  parms = get(stm, CosName("FDecodeParms"))

  io = (util_open(String(filename), "r") |> BufferedInputStream)

  return decode_filter(io, filters, parms)
end

function decode_filter(io, filter::CosNullType, parms::CosObject)
  return io
end

function decode_filter(io, filter::CosName, parms::CosObject)
  f = function_map[filter]
  return f(io, parms)
end

function decode_filter(io, filters::CosArray, parms::CosObject)
  bufstm = io
  for filter in get(filters)
    bufstm = decode_filter(bufstm, filter, parms)
  end
  return bufstm
end

mutable struct PNGPredictorSource{T<:BufferedInputStream}
  input::T
  predictor::UInt8
  columns::Int
  prev::Vector{UInt8}
  curr::Vector{UInt8}
  s::Int
  e::Int
  isResidue::Bool
  isEOF::Bool
  count_scanline::Int
  isClosed::Bool

  function PNGPredictorSource{T}(input::T,pred::Int,columns::Int) where{T<:BufferedInputStream}
    @assert pred >= 10
    prev = zeros(Vector{UInt8}(columns))
    curr = zeros(Vector{UInt8}(columns))
    new(input, pred - 10,columns,prev,curr,0,0,false, false, 0, false)
  end
end

function close(source::PNGPredictorSource)
  source.isClosed=true
  close(source.input)
end

function apply_flate_params(input::BufferedInputStream, parms::CosDict)
  predictor = get(parms, CosName("Predictor"))
  colors    = get(parms, CosName("Colors"))
  bitspercomponent = get(parms, CosName("BitsPerComponent"))
  columns = get(parms, CosName("Columns"))

  predictor_n = (predictor!=CosNull) ? get(predictor) : 0
  colors_n = (colors!=CosNull) ? get(predictor) : 0
  bitspercomponent_n = (bitspercomponent!=CosNull) ? get(bitspercomponent) : 0
  columns_n = (columns !=CosNull) ? get(columns) : 0

  #@printf "Predictor %d\n" predictor_n
  #@printf "Columns %d\n" columns_n

  source = PNGPredictorSource{BufferedInputStream}(input, predictor_n, columns_n)

  return (predictor_n == 2) ? error(E_NOT_IMPLEMENTED) :
         (predictor_n >= 10) ? BufferedInputStream(source) : input
end

function eof(source::PNGPredictorSource)
  return eof(source.input) || source.isEOF
end

function BufferedStreams.readbytes!{T<:BufferedInputStream}(
        source::PNGPredictorSource{T},
        buffer::AbstractArray{UInt8},
        from::Int, to::Int)
  count = 0
  while((from <= to) && !eof(source))
    if (source.isResidue)
      nbres = source.e - source.s + 1
      nbbuf = to - from + 1
      isResidue = (nbres > nbbuf)
      nbcpy = isResidue ? nbbuf : nbres
      copy!(buffer, from, source.curr, source.s, nbcpy)

      count = count + nbcpy
      source.s = isResidue ? 0 : (source.s + nbcpy)
      source.isResidue = isResidue

      if (nbres >= nbbuf)
        #@printf "Buffer Size %d\n" count
        return count
      end

      from = from + nbcpy
    else
      load_png_row!(source)
    end
  end
  #@printf "Buffer Size %d\n" count
  return count
end

function png_predictor_rule(source, row, rule)
  if (rule == 0)
    copy!(source.curr, source.s, row, 2, source.e)
  elseif (rule == 1)
    source.curr[1] = row[2]
    for i=2:source.e
      source.curr[i] = source.curr[i-1]+row[i+1]
    end
  elseif (rule == 2)
    for i=1:source.e
      source.curr[i] = source.prev[i]+row[i+1]
    end
  elseif (rule == 3)
    source.curr[1] = source.prev[1]+row[2]
    for i=2:source.e
      avg = div(source.curr[i-1] + source.prev[i],2)
      source.curr[i] = avg+row[i+1]
    end
  elseif (rule == 4)
    source.curr[1] = source.prev[1]+row[2]
    for i=2:source.e
      pred = PaethPredictor(source.curr[i-1], source.prev[i], source.prev[i-1])
      source.curr[i] = pred + row[i+1]
    end
  end
end

#Exactly as coded in https://www.w3.org/TR/PNG-Filters.html
function PaethPredictor(a::Int32, b::Int32, c::Int32)
     # a = left, b = above, c = upper left
     p = a + b - c        # initial estimate
     pa = abs(p - a)      # distances to a, b, c
     pb = abs(p - b)
     pc = abs(p - c)
     #return nearest of a,b,c,
     #breaking ties in order a,b,c.
     return  (pa <= pb && pa <= pc) ? UInt8(a) :
             (pb <= pc) ? UInt8(b) :
              UInt8(c)
end

function load_png_row!(source::PNGPredictorSource)
  if (source.isResidue || eof(source.input))
    return source
  end

  incolumns = source.columns + 1
  row = Vector{UInt8}(incolumns)
  ncols = BufferedStreams.readbytes!(source.input, row, 1, incolumns)

  if (ncols > 1)
    @assert (source.predictor != 5) && (row[1] == source.predictor)
    source.e = ncols-1
    source.s = 1
    #Before loading next scan line preserve the previous
    if (source.count_scanline >= 1)
      copy!(source.prev, source.curr)
    end
    png_predictor_rule(source, row, row[1])
    source.isResidue=true
    source.count_scanline +=1
  else
    source.e = 0
    source.isResidue=false
    source.s = 0
    source.isEOF = true
  end
  return source
end

mutable struct RLEDecodeSource{T<:BufferedInputStream}
  input::T
  run::Vector{UInt8}
  s::UInt8
  e::UInt8
  isResidue::Bool
  isEOD::Bool
  isClosed::Bool
end

function RLEDecodeSource(input::T) where {T<:BufferedInputStream}
  return RLEDecodeSource(input, zeros(Vector{UInt8}(), UInt8, (128,)), 0x00, 0x00, false, false, false)
end


function close(source::RLEDecodeSource)
  source.isClosed=true
  close(source.input)
end

function eof(source::RLEDecodeSource)
  return source.isEOD && eof(source.input)
end

function BufferedStreams.readbytes!{T<:BufferedInputStream}(
        source::RLEDecodeSource{T},
        buffer::AbstractArray{UInt8},
        from::Int, to::Int)
  count = 0
  while((from <= to) && !eof(source))
    if (source.isResidue)
      nbres = source.e - source.s + 1
      nbbuf = to - from + 1
      isResidue = (nbres > nbbuf)
      nbcpy = isResidue ? nbbuf : nbres
      copy!(buffer, from, source.run, source.s, nbcpy)

      count = count + nbcpy

      source.s = isResidue ? 0 : (source.s + nbcpy)
      source.e = isResidue ? 0 : source.e
      source.isResidue = isResidue

      if (nbres >= nbbuf)
        return count
      end

      from = from + nbcpy
    else
      load_rle_input!(source)
    end
  end
  return count
end

function load_rle_input!(source::RLEDecodeSource)
  if (source.isResidue || eof(source.input))
    return source
  end

  lb=[NULL]
  BufferedStreams.readbytes!(source.input, lb, 1, 1)

  source.e = 0
  if (lb[1] == 128)
    source.isEOD = true
    return source
  elseif (lb[1] < 128)
    nb = BufferedStreams.readbytes!(source.input, source.run, 1, lb[1]+1)
    source.e = nb
  else
    if (!eof(source.input))
      c=[NULL]
      BufferedStreams.readbytes!(source.input, c, 1, 1)
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

mutable struct ASCIIHexDecodeSource{T<:BufferedInputStream}
  input::T
  isClosed::Bool
end

ASCIIHexDecodeSource(input::T) where {T<:BufferedInputStream}=
  ASCIIHexDecodeSource(input,false)

function close(source::ASCIIHexDecodeSource)
  source.isClosed=true
  close(source.input)
end

function eof(source::ASCIIHexDecodeSource)
  return eof(source.input)
end

function BufferedStreams.readbytes!{T<:BufferedInputStream}(
        source::ASCIIHexDecodeSource{T},
        buffer::AbstractArray{UInt8},
        from::Int, to::Int)
  nbneeded = to - from + 1
  nbread   = nbneeded*2
  data=Vector{UInt8}(nbread)

  ndata = BufferedStreams.readbytes!(source.input, data, 1, nbread)
  if (ndata < nbread)
    if (rem(ndata,2)==1)
      ndata = ndata + 1
      data[ndata] = DIGIT_ZERO
    end
  end
  nbreturn = ndata / 2

  i = j = 0
  c = n = UInt(0) # Ensuring computation at the word boundary.
  while i < nbreturn
    n = 0
    c = data[i+=1]
    n = DIGIT_ZERO    <= c <= DIGIT_NINE    ? c - DIGIT_ZERO :
        LATIN_A       <= c <= LATIN_F       ? c - LATIN_A + 10 :
        LATIN_UPPER_A <= c <= LATIN_UPPER_F ? c - LATIN_UPPER_A + 10 :
        error("Input string isn't a hexadecimal string")
    c = data[i+=1]
    n = DIGIT_ZERO    <= c <= DIGIT_NINE    ? n << 4 + c - DIGIT_ZERO :
        LATIN_A       <= c <= LATIN_F       ? n << 4 + c - LATIN_A + 10 :
        LATIN_UPPER_A <= c <= LATIN_UPPER_F ? n << 4 + c - LATIN_UPPER_A + 10 :
        error("Input string isn't a hexadecimal string")
    buffer[j+=1] = n
  end
  return nbreturn
end

function decode_asciihex(input::BufferedInputStream)
  return BufferedInputStream(ASCIIHexDecodeSource(input))
end

#This is still buggy. Needs to be worked upon.

mutable struct ASCII85DecodeSource{T<:BufferedInputStream}
  input::T
  residue::Vector{UInt8}
  isEOF::Bool
  len::Int
  s::Int
  isPending::Bool
  isClosed::Bool
  function ASCII85DecodeSource{T}(t::T,r::Vector{UInt8},isEOF::Bool) where{T<:BufferedInputStream}
    return new(t,r,isEOF,4,1,false, false)
  end
end

ASCII85DecodeSource{T<:BufferedInputStream}(t::T)=ASCII85DecodeSource{T}(t, Vector{UInt8}(4),false)

function close(source::ASCII85DecodeSource)
  source.isClosed=true
  close(source.input)
end

eof(source::ASCII85DecodeSource)=(source.isEOF || eof(source.input))

function BufferedStreams.readbytes!{T<:BufferedInputStream}(
        source::ASCII85DecodeSource{T},
        buffer::AbstractArray{UInt8},
        from::Int, to::Int)
  ofrom=from

  if (source.isPending)
    nread = source.len - source.s + 1
    if (from + nread <= to)
      copy!(buffer, from, source.residue, source.s, nread)
      from += nread
      source.s = 1
      source.len = 4
      source.isPending = false
    else
      nbytes = to - from + 1
      copy!(buffer, from, source.residue, 1, nbytes)
      from+=nbytes
      source.s = nbytes+1
      source.isPending = true
      return nbytes
    end
  end

  while(from <= to) && !eof(source)
    nread=read_next_ascii85_token(source)
    if (from + nread <= to)
      copy!(buffer, from, source.residue, 1, nread)
      from += nread
      source.isPending = false
    else
      nbytes = to - from + 1
      copy!(buffer, from, source.residue, 1, nbytes)
      from+=nbytes
      source.s = nbytes+1
      source.isPending = true
    end
  end

  return from-ofrom+1
end

function read_next_ascii85_token(source::ASCII85DecodeSource)
  if(source.isPending)
    return 0
  end

  b = read(source.input,UInt8)

  count = 1
  if (b == LATIN_Z)
    fill!(source.residue,0)
    source.isPending = true
    return(source.len=4)
  elseif (b == TILDE)
    b = read(source.input, UInt8)
    if (b == GREATER_THAN)
      source.isEOF = true
      source.isPending = false
      return (source.len=0)
    else
      error(E_UNEXPECTED_EOF)
    end
  elseif ispdfspace(b)
    count = 0
  end

  n::UInt32 = 0

  if (count == 1)
    n = b-BANG
    @assert(0 <= n <= 84)
  end
  while(count < 5)&& !eof(source)
    b = peek(source.input)
    if (BANG <= b <= LATIN_U)
      n *= 85
      skip(source.input,1)
      n += (b-BANG)
      count+=1
    elseif (b == TILDE)
      break
    elseif ispdfspace(b)
      skip(source.input,1)
      continue
    else
      error(E_UNEXPECTED_CHAR)
    end
  end

  sz = 0
  for i=(count-1):-1:1
    source.residue[i] = rem(n,256)
    n = div(n, 256)
    sz += 1
  end

  source.isPending = (sz > 0)
  return (source.len=sz)
end


function decode_ascii85(input::BufferedInputStream)
  return BufferedInputStream(ASCII85DecodeSource(input))
end
