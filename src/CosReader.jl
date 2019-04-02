export parse_value,
get_pdfcontentops

import Base: peek

#This function is for testing only
function parse_data(filename)
    ps=util_open(filename,"r")
    try
        while(!eof(ps))
            println(parse_value(ps))
            chomp_space!(ps)
        end
    finally
        util_close(ps)
    end
end

"""
Given a `IOStream`, after possibly any amount of whitespace, return the next
parseable value.
"""
function parse_value(ps::IO, fparse_more=x->nothing)
    chomp_space!(ps)
    byte = UInt8(peek(ps))
    byte == LEFT_PAREN ? parse_string(ps) :
    byte == LESS_THAN  ? parse_xstring(ps) :
    byte == PERCENT    ? parse_comment(ps) :
    byte == SOLIDUS    ? parse_name(ps) :
    byte == MINUS_SIGN ||
        byte == PLUS_SIGN || byte == PERIOD ? parse_number(ps) :
    ispdfdigit(byte)   ? try_parse_indirect_reference(ps) :
    byte == LEFT_SB    ? parse_array(ps) :
    parse_pdfOpsOrConst(ps, fparse_more)
end

function parse_comment(ps::IO)
    b = Vector{UInt8}()
    skip(ps,1)  # skip comment marker
    while true
        c = advance!(ps)
        if is_crorlf(c)
            break
        end
        push!(b, c)
    end
    chomp_space!(ps)
    return CosComment(b)
end

function parse_name(ps::IO)
    b = UInt8[]
    skipv(ps,SOLIDUS)  #skip solidus and ensure it
    while true
        c = ps |> _peekb
        if ispdfspace(c) || ispdfdelimiter(c)
            break
        elseif (c == NUMBER_SIGN)
            skip(ps,1)
            #Now look for 2 hex numbers
            c1 = ps |> _peekb
            skip(ps,1)
            c2 = ps |> _peekb
            if ispdfxdigit(c1) && ispdfxdigit(c2)
                c = UInt8(gethexval(c1)*16+gethexval(c2))
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

function parse_pdfOpsOrConst(ps::IO, fparse_more::Function)
  b = UInt8[]
  while !eof(ps)
      c = ps |> _peekb
      if ispdfspace(c) || ispdfdelimiter(c)
          break
      end
      skip(ps, 1)
      push!(b, c)
  end
  chomp_space!(ps)
  obj = get_pdfconstant(b)
  obj != nothing && return obj
  return fparse_more(b)
end

function get_pdfconstant(b::Vector{UInt8})
    b == [LATIN_T,LATIN_R,LATIN_U,LATIN_E]              && return CosTrue
    b == [LATIN_F,LATIN_A, LATIN_L, LATIN_S, LATIN_E]   && return CosFalse
    b == [LATIN_N, LATIN_U, LATIN_L, LATIN_L]           && return CosNull
    return nothing
end

function parse_array(ps::IO)
    result=CosArray()
    @inbounds skip(ps,1)  # Skip over opening '['
    chomp_space!(ps)
    if ps |> _peekb != RIGHT_SB  # special case for empty array
        @inbounds while true
            push!(result.val, parse_value(ps))
            chomp_space!(ps)
            b = ps |> _peekb
            b == RIGHT_SB && break
        end
    end

    @inbounds skip(ps,1)
    chomp_space!(ps)
    result
end

function read_octal_escape!(c, ps)
    local n::UInt8 = getnumval(c)
    for _ in 1:2
        b = ps |> _peekb
        !ispdfodigit(b) && return n
        n = (n << 3) + getnumval(b)
        skip(ps,1)
    end
    return n
end


function parse_string(ps::IO)
  b = UInt8[]
  skip(ps,1)  # skip opening quote
  local paren_cnt = 0
  while true
    c = advance!(ps)

    if c == BACKSLASH
      c = advance!(ps)
      if ispdfodigit(c) #Read octal digits
        append!(b, read_octal_escape!(c,ps))
      elseif is_crorlf(c) #ignore the solidus, EOLs and move on
        chomp_space!(ps)
      else
        c = get(ESCAPES, c, 0x00)
        c == 0x00 && error(E_BAD_ESCAPE)
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
        return CosLiteralString(b)
      end
    end
    push!(b, c)
  end
end


function parse_xstring(ps::IO)
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
            return CosXString(b)
        elseif !ispdfxdigit(c)
            _error(E_UNEXPECTED_CHAR, ps)
        else
            count +=1
        end
        push!(b, c)
    end
end

function parse_dict(ps::IO)
    #Move the cursor beyond < char
    chomp_space!(ps)

    dict=CosDict()

    while(true)
        # Empty dict File 431 stillhq
        if ps |> _peekb == SOLIDUS
            key = parse_name(ps)
            chomp_space!(ps)

            val = parse_value(ps)
            if (val !== CosNull)
                dict.val[key] = val
            end
        end

        chomp_space!(ps)

        c = ps |> _peekb
        (c == SOLIDUS) && continue
        skip(ps, 1)
        if c == GREATER_THAN
            skipv(ps, GREATER_THAN)
            break
        end
    end
    chomp_space!(ps)
    return dict
end

function ensure_line_feed_eol(ps::IO)
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
function read_internal_stream_data(ps::IO, extent::CosDict, len::Int)
    if get(extent, CosName("F")) != CosNull
        return false
    end

    (path,io) = get_tempfilepath()
    try
        data = read(ps,len)
        write(io, data)
    finally
        util_close(io)
    end

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


mutable struct CosObjectLoc
    loc::Int
    stm::IDDNRef{CosObjectStream}
    obj::CosObject
    CosObjectLoc(l, s=CosNull, o=CosNull) = new(l, s, o)
end

process_stream_length(stmlen::CosInt,
                      ps::IO,
                      hoffset::Int,
                      xref::Dict{CosIndirectObjectRef, CosObjectLoc})=stmlen

function process_stream_length(stmlen::CosIndirectObjectRef,
                               ps::IO,
                               hoffset::Int,
                               xref::Dict{CosIndirectObjectRef, CosObjectLoc})
    cosObjectLoc = xref[stmlen]
    if (cosObjectLoc.obj === CosNull)
        seek(ps, cosObjectLoc.loc + hoffset)
        lenobj = parse_indirect_obj(ps, hoffset, xref)
        if (lenobj != CosNull)
            cosObjectLoc.obj = lenobj
        end
    end
    return cosObjectLoc.obj
end

function postprocess_indirect_object(ps::IO, hoffset::Int, obj::CosDict,
                                     xref::Dict{CosIndirectObjectRef,
                                                CosObjectLoc})
    if locate_keyword!(ps,STREAM) == 0
        ensure_line_feed_eol(ps)
        pos = position(ps)
        
        stmlen = get(obj, CosName("Length"))

        lenobj = process_stream_length(stmlen, ps, hoffset, xref)

        len = get(lenobj)

        if (lenobj != stmlen)
            set!(obj, CosName("Length"), lenobj)
        end

        seek(ps, pos)

        # Here you can make sure file data is decoded into a file
        # later it can be made into a memory based on size etc.
        #Since, these are temporary files the spec is system file only
        isInternal = read_internal_stream_data(ps, obj, len)

        obj = CosStream(obj, isInternal)

        #Now eat away the ENDSTREAM token
        chomp_space!(ps)
        skipv(ps,ENDSTREAM)
        obj = createObjectStreams(obj)
    end
    return obj
end

postprocess_indirect_object(ps::IO,
                            hoffset::Int,
                            obj::CosObject,
                            xref::Dict{CosIndirectObjectRef, CosObjectLoc}) = obj

function parse_indirect_obj(ps::IO,
                            hoffset::Int,
                            xref::Dict{CosIndirectObjectRef, CosObjectLoc})
    objn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    genn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    skipv(ps, OBJ)
    obj = parse_value(ps)
    chomp_space!(ps)
    obj = postprocess_indirect_object(ps, hoffset, obj, xref)
    chomp_space!(ps)
    skipv(ps,ENDOBJ)
    return CosIndirectObject(objn, genn, obj)
end

function parse_indirect_ref(ps::IO)
    objn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    genn = parse_unsignednumber(ps).val
    chomp_space!(ps)
    skipv(ps, LATIN_UPPER_R)
    chomp_space!(ps)
    return CosIndirectObjectRef(objn, genn)
end

function try_parse_indirect_reference(ps::IO)
    nobj = parse_number(ps)
    if isa(nobj,CosFloat)
        return nobj
    end
    chomp_space!(ps)
    mark(ps)
    if ispdfdigit(ps |> _peekb)
        objn = nobj.val
        genn = parse_unsignednumber(ps).val
        chomp_space!(ps)
        if (ps |> _peekb == LATIN_UPPER_R)
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
function float_from_bytes(bytes::Vector{UInt8})
    res = tryparse(Float64, String(bytes))
    res === nothing && return res
    res isa Float64 && return res
    isnull(res) && return nothing
    return get(res)
end

"""
Parse an integer from the given bytes vector, starting at `from` and ending at
the byte before `to`. Bytes enclosed should all be ASCII characters.
"""
function int_from_bytes(bytes::Vector{UInt8})
    from = 1
    to = length(bytes)
    @inbounds isnegative = bytes[from] == MINUS_SIGN ? (from += 1; true) : false
    num = Int(0)
    @inbounds for i in from:to
        num = Int(10) * num + Int(bytes[i] - DIGIT_ZERO)
    end
    return ifelse(isnegative, -num, num)
end

function number_from_bytes(ps::IO, isint::Bool, bytes::Vector{UInt8})
    from = 1
    to = length(bytes)
    if isint
        @inbounds if to == from && bytes[from] == MINUS_SIGN
            _error(E_BAD_NUMBER, ps)
        end
        num = int_from_bytes(bytes)
        return CosInt(num)
    else
        res = float_from_bytes(bytes)
        res === nothing && _error(E_BAD_NUMBER, ps)
        return CosFloat(res)
    end
end

function parse_unsignednumber(ps::IO)
    number = UInt8[]
    isint = true
    while true
        c = ps |> _peekb
        if ispdfdigit(c)
            push!(number, UInt8(c))
        else
            break
        end
        skip(ps,1)
    end
    chomp_space!(ps)
    return number_from_bytes(ps, isint, number)
end


function parse_number(ps::IO)
    number = UInt8[]
    isint = true

    while true
        c = ps |> _peekb

        if ispdfdigit(c) || c == MINUS_SIGN
            push!(number, UInt8(c))
        elseif c == PLUS_SIGN
        elseif c==DECIMAL_POINT
            push!(number, UInt8(c))
            isint = false
        else
            break
        end

        skip(ps, 1)
    end
    chomp_space!(ps)
    return number_from_bytes(ps, isint, number)
end
