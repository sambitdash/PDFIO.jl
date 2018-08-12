using ..Cos
using ..Common

latin_charset_encoding() = load_data_file("latin-charset-encoding.txt")

function get_latin_charset_dict(col)
    dict = Dict{UInt8,CosName}()
    m = latin_charset_encoding()
    map(m[:,1], m[:,col]) do x, y
        if y != "-"
            v = to_uint8(y)
            dict[v] = CosName(strip(x))
        end
    end
    return dict
end

const STDEncoding_to_GlyphName = get_latin_charset_dict(2)
MACEncoding_to_GlyphName = get_latin_charset_dict(3)
WINEncoding_to_GlyphName = get_latin_charset_dict(4)
const PDFEncoding_to_Glyphname = get_latin_charset_dict(5)

#Special handling for few cases as per spec
WINEncoding_to_GlyphName[0xAD] = cn"sfthyphen"
WINEncoding_to_GlyphName[0xA0] = cn"colon"

MACEncoding_to_GlyphName[0xCA] = cn"colon"

function reverse_dict(dict)
    rdict = Dict()
    for (x, y) in dict
        rdict[y] = x
    end
    return rdict
end

const GlyphName_to_STDEncoding = reverse_dict(STDEncoding_to_GlyphName)
const GlyphName_to_MACEncoding = reverse_dict(MACEncoding_to_GlyphName)
const GlyphName_to_WINEncoding = reverse_dict(WINEncoding_to_GlyphName)
const Glyphname_to_PDFEncoding = reverse_dict(PDFEncoding_to_Glyphname)

macexpt_charset_encoding() = load_data_file("mac-expert.txt")
symbols_charset_encoding() = load_data_file("symbols-encoding.txt")
zapf_charset_encoding()    = load_data_file("zapfdingbats-encoding.txt")

function get_charset_dict(f::Function)
    dict = Dict{UInt8,CosName}()
    m = f()
    map(m[:,2], m[:,3]) do x, y
        v = to_uint8(y)
        dict[v] = CosName(strip(x))
    end
    return dict
end

const MEXEncoding_to_GlyphName = get_charset_dict(macexpt_charset_encoding)
const SYMEncoding_to_GlyphName = get_charset_dict(symbols_charset_encoding)
const ZAPEncoding_to_GlyphName = get_charset_dict(zapf_charset_encoding)

const Glyphname_to_MEXEncoding = reverse_dict(MEXEncoding_to_GlyphName)
const GlyphName_to_SYMEncoding = reverse_dict(SYMEncoding_to_GlyphName)
const GlyphName_to_ZAPEncoding = reverse_dict(ZAPEncoding_to_GlyphName)

using AdobeGlyphList

function agl_mapping_to_dict(m)
    dict = Dict{CosName, Char}()
    map(m[:,1], m[:,2]) do x, y
        dict[CosName(strip(x))] = y
    end
    return dict
end

const AGL_Glyph_to_Unicode = agl_mapping_to_dict(agl())
const AGL_ZAP_to_Unicode   = agl_mapping_to_dict(zapfdingbats())
const AGL_Unicode_to_Glyph = reverse_dict(AGL_Glyph_to_Unicode)
const AGL_Unicode_to_ZAP   = reverse_dict(AGL_ZAP_to_Unicode)

const STDEncoding_to_Unicode = dict_remap(STDEncoding_to_GlyphName, AGL_Glyph_to_Unicode)
const MACEncoding_to_Unicode = dict_remap(MACEncoding_to_GlyphName, AGL_Glyph_to_Unicode)
const WINEncoding_to_Unicode = dict_remap(WINEncoding_to_GlyphName, AGL_Glyph_to_Unicode)

const MEXEncoding_to_Unicode = dict_remap(MEXEncoding_to_GlyphName, AGL_Glyph_to_Unicode)
const SYMEncoding_to_Unicode = dict_remap(SYMEncoding_to_GlyphName, AGL_Glyph_to_Unicode)
const ZAPEncoding_to_Unicode = dict_remap(ZAPEncoding_to_GlyphName, AGL_ZAP_to_Unicode)
