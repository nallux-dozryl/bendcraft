import Base
import ./generic_resource_world_sample.bend as GS
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as C
import ./world_resource_frame.bend as WRF

def error_text(error:C.Error) -> String:
  C.Error{code,resource,detail} = error
  code ++ ":" ++ resource ++ ":" ++ detail

def result(value:CW.Assets & Result<&2,&2,C.Error,Image>) -> CW.Assets & Result<&2,&2,String,Image>:
  (assets,status) = value
  match status:
    case Fail{error}: (assets,Fail{error_text(error)})
    case Done{image}: (assets,Done{image})

def framed(value:Result<&2,&2,C.Error,CW.Frame>,assets:CW.Assets,width:U32,height:U32) -> CW.Assets & Result<&2,&2,String,Image>:
  match value:
    case Fail{error}: (assets,Fail{error_text(error)})
    case Done{frame}: result(WRF.draw_catalog(frame,assets,width,height))

def informed(sample:GS.Sample,width:U32,height:U32,value:CW.Assets & CW.Info) -> CW.Assets & Result<&2,&2,String,Image>:
  (assets,info) = value
  framed(GS.draw_frame(sample,info),assets,width,height)

# Real presenter consumers call this after a correlated CatalogFrameReply.
# The complete resource/texture owner returns on decode/bind/render failures.
def draw(sample:GS.Sample,assets:CW.Assets,width:U32,height:U32) -> CW.Assets & Result<&2,&2,String,Image>:
  informed(sample,width,height,CW.info(assets))
