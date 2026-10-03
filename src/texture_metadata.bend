import Base
import ./json.bend as J
import ./resource_json.bend as Q
import ./float_parse.bend as F

# The 26.3 TextureMetadataSection CODEC under JsonOps.INSTANCE.
# This is metadata interpretation, not sampler/mipmap execution or admission.
type Strategy is Data:
  Auto{}
  Mean{}
  Cutout{}
  StrictCutout{}
  DarkCutout{}

type Metadata is Data:
  Metadata{blur:Bool,clamp:Bool,strategy:Strategy,alpha_cutoff_bias:F32}

type Error is Data:
  Error{code:String,field:String,message:String}

def defaults() -> Metadata:
  Metadata{False{},False{},Auto{},0.0}

def strategy_name(value:Strategy) -> String:
  match value:
    case Auto{}: "auto"
    case Mean{}: "mean"
    case Cutout{}: "cutout"
    case StrictCutout{}: "strict_cutout"
    case DarkCutout{}: "dark_cutout"

def strategy_string(value:String) -> Result<&2,&2,Error,Strategy>:
  match value:
    case "auto": Done{Auto{}}
    case "mean": Done{Mean{}}
    case "cutout": Done{Cutout{}}
    case "strict_cutout": Done{StrictCutout{}}
    case "dark_cutout": Done{DarkCutout{}}
    case _: Fail{Error{"UnknownStrategy","mipmap_strategy","Unknown mipmap strategy"}}

# OptionalFieldCodec treats a null member like an absent member. JsonOps does
# not coerce strings/numbers to booleans or numbers/booleans to strings.
def boolean(value:Maybe<&2,J.Value>,field:String) -> Result<&2,&2,Error,Bool>:
  match value:
    case None{}: Done{False{}}
    case Some{J.JNull{}}: Done{False{}}
    case Some{J.JBool{v}}: Done{v}
    case _: Fail{Error{"InvalidBoolean",field,"Expected a JSON boolean"}}

def strategy(value:Maybe<&2,J.Value>) -> Result<&2,&2,Error,Strategy>:
  match value:
    case None{}: Done{Auto{}}
    case Some{J.JNull{}}: Done{Auto{}}
    case Some{J.JString{s}}: strategy_string(s)
    case _: Fail{Error{"InvalidStrategy","mipmap_strategy","Expected a JSON string"}}

def number_result(value:Result<&2,&2,String,F32>) -> Result<&2,&2,Error,F32>:
  match value:
    case Done{v}: Done{v}
    case Fail{message}: Fail{Error{"NumericLimitOrSyntax","alpha_cutoff_bias",message}}

def bias(value:Maybe<&2,J.Value>) -> Result<&2,&2,Error,F32>:
  match value:
    case None{}: Done{0.0}
    case Some{J.JNull{}}: Done{0.0}
    case Some{J.JNumber{raw}}: number_result(F.parse_f32(raw))
    case _: Fail{Error{"InvalidNumber","alpha_cutoff_bias","Expected a JSON number"}}

# The parsed J.Value object has unique keys. ResourceJson preserves the last
# duplicate before this call. Unknown members are ignored by the official codec.
def decode_section(+value:J.Value) -> Result<&2,&2,Error,Metadata>:
  match value:
    case J.JObject{members}:
      do Result<&2,&2,Error,Metadata>:
        blur : Bool <- boolean(J.member(value,"blur"),"blur")
        clamp : Bool <- boolean(J.member(value,"clamp"),"clamp")
        mipmaps : Strategy <- strategy(J.member(value,"mipmap_strategy"))
        alpha : F32 <- bias(J.member(value,"alpha_cutoff_bias"))
        Done{Metadata{blur,clamp,mipmaps,alpha}}
    case _: Fail{Error{"InvalidSection","texture","Expected a JSON object"}}

def document_section(value:Maybe<&2,J.Value>) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  match value:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2,&2,Error,Maybe<&2,Metadata>>:
        metadata : Metadata <- decode_section(v)
        Done{Some{metadata}}

# ResourceMetadata.getSection distinguishes missing texture from texture:null.
def decode_document(+value:J.Value) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  match value:
    case J.JObject{members}: document_section(J.member(value,"texture"))
    case _: Fail{Error{"InvalidDocument","","Expected a JSON object"}}

def parsed_document(value:Result<&2,&2,String,J.Value>) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  match value:
    case Fail{message}: Fail{Error{"InvalidJson","",message}}
    case Done{v}: decode_document(v)

# Default bounded ResourceJson grammar: first root, initial BOM, last duplicate.
# Input is already a Bend String. UTF-8 byte decoding belongs to the caller;
# Java InputStreamReader replacement and loader strict UTF-8 are distinct policies.
def parse_document(text:String) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  parsed_document(Q.parse(text))

def parse_document_with(text:String,limits:J.Limits) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  parsed_document(Q.parse_with(text,limits))
