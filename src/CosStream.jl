import Base:eof

export cosStreamRemoveFilters

function _not_implemented(input)
  error(E_NOT_IMPLEMENTED)
end

using Libz

using BufferedStreams

"""
Decodes using the LZWDecode compression
"""
function decode_lzw(stm::CosStream)
  print("Ready to decode the LZW stream")
end

function decode_flate(input, parms)
  deflate = ZlibInflateInputStream(input; gzip=false)
  return apply_flate_params(deflate, parms)
end


apply_flate_params(input,parms)=input

using BufferedStreams

function decode_asciihex(input, parms)
  return decode_asciihex(BufferedInputStream(input))
end

function decode_ascii85(input, parms)
  return decode_ascii85(BufferedInputStream(input))
end

function decode_rle(input, parms)
  return decode_rle(BufferedInputStream(input))
end

const function_map = Dict(
   CosName("ASCIIHexDecode") => decode_asciihex,
   CosName("ASCII85Decode") => _not_implemented,
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
    write(filename |> get, data)
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

  io = (open(filename |> get, "r") |> BufferedInputStream)

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

type PNGPredictorSource{T<:BufferedInputStream}
  input::T
  predictor::UInt8
  columns::UInt32
  prev::Vector{UInt8}
  curr::Vector{UInt8}
  s::Int32
  e::Int32
  isResidue::Bool
  isEOF::Bool
  count_scanline::Int32

  function PNGPredictorSource{T}(input::T,pred::Int,columns::Int) where{T<:BufferedInputStream}
    @assert pred >= 10
    prev = zeros(Vector{UInt8}(columns))
    curr = zeros(Vector{UInt8}(columns))
    new(input, pred - 10,columns,prev,curr,0,0,false, false, 0)
  end
end


function apply_flate_params(input::BufferedInputStream, parms::CosDict)
  predictor = get(parms, CosName("Predictor"))
  colors    = get(parms, CosName("Colors"))
  bitspercomponent = get(parms, CosName("BitsPerComponent"))
  columns = get(parms, CosName("Columns"))

  predictor_n = (predictor!=CosNull)?get(predictor):0
  colors_n = (colors!=CosNull)?get(predictor):0
  bitspercomponent_n = (bitspercomponent!=CosNull)?get(bitspercomponent):0
  columns_n = (columns !=CosNull)?get(columns):0

  #@printf "Predictor %d\n" predictor_n
  #@printf "Columns %d\n" columns_n

  source = PNGPredictorSource{BufferedInputStream}(input, predictor_n, columns_n)

  return (predictor_n == 2)? error(E_NOT_IMPLEMENTED):
         (predictor_n >= 10)? BufferedInputStream(source):input
end

function eof(source::PNGPredictorSource)
  return eof(source.input) || source.isEOF
end

function BufferedStreams.readbytes!{T<:BufferedInputStream}(
        source::PNGPredictorSource{T},
        buffer::Vector{UInt8},
        from::Int, to::Int)
  count = 0
  while((from <= to) && !eof(source))
    if (source.isResidue)
      nbres = source.e - source.s + 1
      nbbuf = to - from + 1
      isResidue = (nbres > nbbuf)
      nbcpy = isResidue? nbbuf : nbres
      copy!(buffer, from, source.curr, source.s, nbcpy)

      count = count + nbcpy
      source.s = isResidue? 0: (source.s + nbcpy)
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
     return  (pa <= pb && pa <= pc)? UInt8(a):
             (pb <= pc)? UInt8(b):
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

  ndata = BufferedStreams.readbytes!(source.input, data, 1, nbread)
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
