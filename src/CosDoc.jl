import PDF.Common.Parser

using PDF.Common
using PDF.Common.Parser

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
  trailer::CosDict
  isPDF::Bool
  CosDocImpl(fp::String) = new(fp,open(fp,"r"),"",0,(0,0),
                              Dict{Tuple{Int,Int}, Int}(),
                              CosDict(), false)
end

function cosDocOpen(fp::String)
  doc = CosDocImpl(abspath(fp));
  ps = getParserState(doc.io)
  h = read_header(ps)
  doc.version = (h[1], h[2])
  doc.header = String(h[3])

  doc.isPDF = (doc.header == "PDF")

  doc_trailer_update(ps,doc)

  if doc.isPDF
    read_xref_table(ps,doc)
  end
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

function doc_trailer_update(ps::ParserState, doc::CosDocImpl)
    const TRAILER_REWIND=200

    seek(ps,-TRAILER_REWIND)

    if locate_keyword!(ps,TRAILER,TRAILER_REWIND) >= 0
        _error(E_UNEXPECTED_CHAR,ps)
    end
    #Check for EOL
    chomp_eol!(ps)

    print(Char(current(ps)))
    skip!(ps,LESS_THAN)
    doc.trailer = parse_dict(ps)


    if (doc.isPDF)
      if locate_keyword!(ps,STARTXREF) >= 0
        _error(E_UNEXPECTED_CHAR,ps)
      end
      chomp_space!(ps)
      doc.startxref = parse_number(ps).val
      chomp_space!(ps)
    end

    #Check for EOF
    if locate_keyword!(ps,EOF) >= 0
        _error(E_UNEXPECTED_CHAR,ps)
    end
end


function read_xref_table(ps::ParserState, doc::CosDocImpl)
    seek(ps, doc.startxref)

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
        print(n_entry)
        print("\n")
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
