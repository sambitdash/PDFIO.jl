export parse_value,
       get_pdfcontentops

get_pdfcontentops(b)=error(E_NOT_IMPLEMENTED)

function parse_data(filename)
  ps=BufferedInputStream(open(filename))

  while(!eof(ps))
    println(parse_value(ps))
    chomp_space!(ps)
  end
end

"""
Given a `BufferedInputStream`, after possibly any amount of whitespace, return the next
parseable value.
"""
function parse_value(ps::BufferedInputStream)
    chomp_space!(ps)

    @inbounds byte = peek(ps)
    if byte == LEFT_PAREN
        parse_string(ps)
    elseif byte == LESS_THAN
        parse_xstring(ps)
    elseif byte == PERCENT
        parse_comment(ps)
    elseif byte == SOLIDUS
        parse_name(ps)
    elseif byte == MINUS_SIGN || byte == PLUS_SIGN || byte == PERIOD
        parse_number(ps)
    elseif ispdfdigit(byte)
        try_parse_indirect_reference(ps)
    elseif byte == LEFT_SB
        parse_array(ps)
    else
        parse_pdfOpsOrConst(ps)
    end
end

function parse_comment(ps::BufferedInputStream)
    b = UInt8[]
    skip(ps,1)  # ski opening quote
    while true
        c = advance!(ps)
        if is_crorlf(c)
            break
        end
        push!(b, c)
    end
    chomp_space!(ps)
    return b
end

function parse_name(ps::BufferedInputStream)
    b = UInt8[]
    skip(ps,1)  #skip solidus
    while true
        c = peek(ps)
        if ispdfspace(c) || ispdfdelimiter(c)
            break
        elseif (c == NUMBER_SIGN)
            skip(ps,1)
            #Now look for 2 hex numbers
            c1 = peek(ps)
            skip(ps,1)
            c2 = peek(ps)
            if ispdfxdigit(c1) && ispdfxdigit(c2)
                c = UInt8(c1*16+c2)
            else
                _error(E_UNEXPECTED_CHAR, ps)
            end
        end
        skip(ps,1)
        push!(b, c)
    end
    chomp_space!(ps)
    return CosName(String(b))
end

function parse_pdfOpsOrConst(ps::BufferedInputStream)
  b = UInt8[]

  while true
      c = peek(ps)
      if ispdfspace(c) || ispdfdelimiter(c)
          break
      end
      skip(ps,1)
      push!(b, c)
  end
  chomp_space!(ps)
  obj = get_pdfconstant(b)
  if (obj==nothing)
    obj = get_pdfcontentops(b)
  end
  return obj
end

function get_pdfconstant(b::Vector{UInt8})
  if (b==[LATIN_T,LATIN_R,LATIN_U,LATIN_E])
    return CosTrue
  elseif (b==[LATIN_F,LATIN_A, LATIN_L, LATIN_S, LATIN_E])
    return CosFalse
  elseif (b==[LATIN_N, LATIN_U, LATIN_L, LATIN_L])
    return CosNull
  else
    return nothing
  end
end

function parse_array(ps::BufferedInputStream)
    result=CosArray()
    @inbounds skip(ps,1)  # Skip over opening '['
    chomp_space!(ps)
    if peek(ps) ≠ RIGHT_SB  # special case for empty array
        @inbounds while true
            push!(result.val, parse_value(ps))
            chomp_space!(ps)
            b = peek(ps)
            b == RIGHT_SB && break
        end
    end

    @inbounds skip(ps,1)
    chomp_space!(ps)
    result
end

function read_octal_escape!(c, ps)
    local n::UInt16 = (c << 3)
    for _ in 1:2
        b = advance!(ps)
        n = n << 3
        if (ispdfodigit(b))
            n += b
        else
            retract!(ps)
            break
        end
    end
    n
end


function parse_string(ps::BufferedInputStream)
    b = UInt8[]
    skip(ps,1)  # skip opening quote
    local paren_cnt = 0
    while true
        c = advance!(ps)

        if c == BACKSLASH
            c = advance!(ps)
            if ispdfodigit(c) #Read octal digits
                append!(b, Vector{UInt8}(string(read_octal_escape!(ps))))
            else
                c = get(ESCAPES, c, 0x00)
                c == 0x00 && _error(E_BAD_ESCAPE, ps)
                push!(b, c)
            end
            continue
        elseif c == LEFT_PAREN
            paren_cnt+=1
        elseif c == RIGHT_PAREN
            if (paren_cnt > 0)
                paren_cnt-=1
            else
                chomp_space!(ps)
                return CosLiteralString(String(b))
            end
        end

        push!(b, c)
    end
end


function parse_xstring(ps::BufferedInputStream)
    b = UInt8[]
    skip(ps,1)  # skip open LT

    count = 0
    while true
        c = advance!(ps)
        if c == LESS_THAN
            return parse_dict(ps)
        elseif c == GREATER_THAN
            if count % 2 !=0
                count +=1
                push!(b, NULL)
            end
            chomp_space!(ps)
            return CosXString(String(b))
        elseif !ispdfxdigit(c)
            _error(E_UNEXPECTED_CHAR, ps)
        else
            count +=1
        end
        push!(b, c)
    end
end

function parse_dict(ps::BufferedInputStream)
    #Move the cursor beyond < char
    chomp_space!(ps)

    dict=CosDict()

    while(true)
        @assert peek(ps)==SOLIDUS
        key = parse_name(ps)
        chomp_space!(ps)

        val = parse_value(ps)
        if (val != CosNull)
            dict.val[key] = val
        end

        chomp_space!(ps)

        c = peek(ps)
        if (c == GREATER_THAN)
            skip(ps,1)
            skipv(ps, GREATER_THAN)
            break
        end
        keyfound = false
    end
    chomp_space!(ps)
    return dict
end

function ensure_line_feed_eol(ps::BufferedInputStream)
  c = advance!(ps)
  if (c == RETURN)
    skipv(ps,LINE_FEED)
  elseif (c == LINE_FEED)
    return c
  else
    _error(E_UNEXPECTED_CHAR)
  end
end

"""
Read the internal stream data and externalize to a temp file.
If it's already an externalized stream then false is returned.
The value can be stored in the stream object attribute so that the reverse
process will be carried out for serialization.
"""
function read_internal_stream_data(ps::BufferedInputStream, extent::CosDict, len::Int)
  if get(extent, CosName("F")) != CosNull
    return false
  end

  (path,io) = get_tempfilepath()
  data = read(ps,len)
  write(io, data)
  close(io)

  #Ensuring all the data is written to a file
  set!(extent, CosName("F"), CosLiteralString(path))

  filter = get(extent, CosName("Filter"))
  if (filter != CosNull)
    set!(extent, CosName("FFilter"), filter)
    set!(extent, CosName("Filter"), CosNull)
  end

  parms = get(extent, CosName("DecodeParms"))
  if (parms != CosNull)
    set!(extent, CosName("FDecodeParms"), parms)
    set!(extent, CosName("DecodeParms"),CosNull)
  end

  return true
end


type CosObjectLoc
  loc::Int
  stm::CosObject
  obj::CosObject
  CosObjectLoc(l,s=CosNull,o=CosNull)=new(l,s,o)
end

process_stream_length(stmlen::CosInt,
                      ps::BufferedInputStream,
                      xref::Dict{CosIndirectObjectRef, CosObjectLoc})=stmlen

function process_stream_length(stmlen::CosIndirectObjectRef,
                               ps::BufferedInputStream,
                               xref::Dict{CosIndirectObjectRef, CosObjectLoc})
  cosObjectLoc = xref[stmlen]
  if (cosObjectLoc.obj === CosNull)
    seek(ps,cosObjectLoc.loc)
    lenobj = parse_indirect_obj(ps,xref)
    if (lenobj != CosNull)
      cosObjectLoc.obj = lenobj
    end
  end
  return cosObjectLoc.obj
end

function postprocess_indirect_object(ps::BufferedInputStream, obj::CosDict,
                              xref::Dict{CosIndirectObjectRef, CosObjectLoc})
  if locate_keyword!(ps,STREAM) == 0
    ensure_line_feed_eol(ps)
    pos = position(ps)

    stmlen = get(obj, CosName("Length"))

    lenobj = process_stream_length(stmlen, ps, xref)

    len = get(lenobj)

    if (lenobj != stmlen)
      set!(obj, CosName("Length"), lenobj)
    end

    seek(ps,pos)

    # Here you can make sure file data is decoded into a file
    # later it can be made into a memory based on size etc.
    #Since, these are temporary files the spec is system file only
    isInternal = read_internal_stream_data(ps,obj,len)

    obj = CosStream(obj, isInternal)

    #Now eat away the ENDSTREAM token
    chomp_space!(ps)
    skipv(ps,ENDSTREAM)
    obj = createObjectStreams(obj)
  end
  return obj
end

postprocess_indirect_object(ps::BufferedInputStream, obj::CosObject,
                            xref::Dict{CosIndirectObjectRef, CosObjectLoc})=obj

function parse_indirect_obj(ps::BufferedInputStream,
                            xref::Dict{CosIndirectObjectRef, CosObjectLoc})
    objn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    genn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    skipv(ps, OBJ)
    obj = parse_value(ps)
    chomp_space!(ps)
    obj = postprocess_indirect_object(ps, obj, xref)
    chomp_space!(ps)
    skipv(ps,ENDOBJ)
    return CosIndirectObject(objn, genn, obj)
end

function parse_indirect_ref(ps::BufferedInputStream)
    objn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    genn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    skipv(ps, LATIN_UPPER_R)
    chomp_space!(ps)
    return CosIndirectObjectRef(objn, genn)
end

function try_parse_indirect_reference(ps::BufferedInputStream)
    nobj = parse_number(ps)
    if isa(nobj,CosFloat)
        return nobj
    end
    chomp_space!(ps)
    mark(ps)
    if ispdfdigit(peek(ps))
        objn = nobj.val
        genn = parse_unsignednumber(ps).val
        chomp_space!(ps)
        if (peek(ps)==LATIN_UPPER_R)
          unmark(ps)
          skip(ps,1)
          chomp_space!(ps)
          return CosIndirectObjectRef(objn, genn)
        else
          reset(ps)
          chomp_space!(ps)
          return nobj
        end
    else
        unmark(ps)
        chomp_space!(ps)
        return nobj
    end
end


"""
Return `true` if the given bytes vector, starting at `from` and ending at `to`,
has a leading zero.
"""
function hasleadingzero(bytes::Vector{UInt8}, from::Int, to::Int)
    c = bytes[from]
    from + 1 < to && c == UInt8('-') &&
            bytes[from + 1] == DIGIT_ZERO && ispdfdigit(bytes[from + 2]) ||
    from < to && to > from + 1 && c == DIGIT_ZERO &&
            ispdfdigit(bytes[from + 1])
end

"""
Parse a float from the given bytes vector, starting at `from` and ending at the
byte before `to`. Bytes enclosed should all be ASCII characters.
"""
function float_from_bytes(bytes::Vector{UInt8}, from::Int, to::Int)
    # The ccall is not ideal (Base.tryparse would be better), but it actually
    # makes an 2× difference to performance
    ccall(:jl_try_substrtod, Nullable{Float64},
            (Ptr{UInt8}, Csize_t, Csize_t), bytes, from - 1, to - from + 1)
end

"""
Parse an integer from the given bytes vector, starting at `from` and ending at
the byte before `to`. Bytes enclosed should all be ASCII characters.
"""
function int_from_bytes(bytes::Vector{UInt8}, from::Int, to::Int)
    @inbounds isnegative = bytes[from] == MINUS_SIGN ? (from += 1; true) : false
    num = Int64(0)
    @inbounds for i in from:to
        num = Int64(10) * num + Int64(bytes[i] - DIGIT_ZERO)
    end
    return ifelse(isnegative, -num, num)
end

function number_from_bytes(ps::BufferedInputStream, isint::Bool,
                           bytes::Vector{UInt8}, from::Int, to::Int)
    #=
    @inbounds if hasleadingzero(bytes, from, to)
        _error(E_LEADING_ZERO, ps)
    end
=#

    if isint
        @inbounds if to == from && bytes[from] == MINUS_SIGN
            _error(E_BAD_NUMBER, ps)
        end
        num = int_from_bytes(bytes, from, to)
        return CosInt(num)

    else
        res = float_from_bytes(bytes, from, to)
        if isnull(res)
            _error(E_BAD_NUMBER, ps)
        else
            return CosFloat(get(res))
        end
    end
end

function parse_unsignednumber(ps::BufferedInputStream)
    number = UInt8[]
    isint = true

    while true
        c = peek(ps)
        if ispdfdigit(c)
            push!(number, UInt8(c))
        else
            break
        end
        skip(ps,1)
    end
    chomp_space!(ps)
    return number_from_bytes(ps, isint, number, 1, length(number))
end


function parse_number(ps::BufferedInputStream)
    number = UInt8[]
    isint = true

    while true
        c = peek(ps)

        if ispdfdigit(c) || c == MINUS_SIGN
            push!(number, UInt8(c))
        elseif c == PLUS_SIGN
        elseif c==DECIMAL_POINT
            push!(number, UInt8(c))
            isint = false
        else
            break
        end

        skip(ps,1)
    end
    chomp_space!(ps)
    return number_from_bytes(ps, isint, number, 1, length(number))
end
