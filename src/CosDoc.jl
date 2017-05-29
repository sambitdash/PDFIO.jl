export CosDoc,
       cosDocOpen

abstract CosDoc

type CosDocImpl <: CosDoc
  filepath::String
  io::IO
  header::String
  startxref::Int
  version::Tuple{Int,Int}
  xref::Dict{Tuple{Int,Int}, Int}
  trailer::Array{CosDict,1}
  isPDF::Bool
  CosDocImpl(fp::String) = new(fp,open(fp,"r"),"",0,(0,0),
                              Dict{Tuple{Int,Int}, Int}(),
                              [], false)
end


const Trailer_Root=CosName("Root")
const Trailer_Prev=CosName("Prev")

function cosDocOpen(fp::String)
  doc = CosDocImpl(abspath(fp));
  ps = getParserState(doc.io)
  h = read_header(ps)
  doc.version = (h[1], h[2])
  doc.header = String(h[3])

  doc.isPDF = (doc.header == "PDF")

  doc_trailer_update(ps,doc)

  return doc
end

function read_header(ps)
  skip!(ps,PERCENT)
  b = UInt8[]
  c = advance!(ps)
  while(c != MINUS_SIGN)
    push!(b,c)
    c=advance!(ps)
  end
  major = advance!(ps)
  if ispdfdigit(major)
      major -= DIGIT_ZERO
  else
      _error(E_BAD_HEADER, ps)
  end
  skip!(ps,PERIOD)
  minor = advance!(ps)

  if ispdfdigit(minor)
      minor -= DIGIT_ZERO
  else
      _error(E_BAD_HEADER, ps)
  end
  return [major,minor,b]
end


function read_trailer(ps::ParserState, lookahead::Int)
  if locate_keyword!(ps,TRAILER,lookahead) < 0
      _error(E_UNEXPECTED_CHAR,ps)
  end
  #Check for EOL
  chomp_eol!(ps)
  skip!(ps,LESS_THAN)

  dict = parse_dict(ps)
  chomp_space!(ps)

  return dict
end

function doc_trailer_update(ps::ParserState, doc::CosDocImpl)
  const TRAILER_REWIND=200

  seek(ps,-TRAILER_REWIND)

  trailer = read_trailer(ps, TRAILER_REWIND)

  if (get(trailer, Trailer_Root) != CosNull)
    # doc trailer must contain the root, the trailer following the
    # xref following startxref will have it.
    doc.trailer = trailer
  end

  if (doc.isPDF)
    if locate_keyword!(ps,STARTXREF) != 0
      _error(E_UNEXPECTED_CHAR,ps)
    end
    chomp_space!(ps)
    doc.startxref = parse_number(ps).val
    chomp_space!(ps)
  end

  #Check for EOF
  if locate_keyword!(ps,EOF) != 0
      _error(E_UNEXPECTED_CHAR,ps)
  end

  if doc.isPDF
    seek(ps, doc.startxref)
    found = false
    while(true)
      read_xref_table(ps,doc)
      trailer = read_trailer(ps, length(TRAILER))

      if (!found)
        if (get(trailer, Trailer_Root) == CosNull)
          _error(E_BAD_TRAILER,ps)
        else
          push!(doc.trailer, trailer)
        end
        found = true
      else
        push!(doc.trailer, trailer)
      end
      prev = get(trailer, Trailer_Prev)
      if (prev == CosNull)
        break
      end
      seek(ps, prev.val)
    end
  end

end


function read_xref_table(ps::ParserState, doc::CosDocImpl)
    skip!(ps, XREF)
    chomp_eol!(ps)


    while (true)
        if !ispdfdigit(current(ps))
            break
        end
        oid = parse_unsignednumber(ps).val
        skip!(ps, SPACE)
        n_entry = parse_unsignednumber(ps).val
        chomp_space!(ps)

        for i=1:n_entry
            v = UInt8[]

            for j = 1:20
                push!(v, advance!(ps))
            end

            if (v[18] != LATIN_F)
                tuple = (oid, parse(Int,String(v[12:16])))

                doc.xref[tuple] = parse(Int,String(v[1:10]))
            end

            oid +=1
        end
    end
    return doc.xref
end
