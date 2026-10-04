import Base
import ./player_presentation.bend as Presentation

type Options is Data:
  Options{frames:Maybe<&2,Nat>,jar:String,settings:Presentation.Settings,item_table:String}

def defaults() -> Options:
  Options{None{},"/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar",Presentation.Settings{0,0,100,0,False{},False{}},"generated/reference_item_metadata.tsv"}

def count(options:Options,result:Maybe<&2,U32>) -> Result<&2,&2,String,Options>:
  match options result:
    case _ None{}: Fail{"--frames requires an unsigned integer"}
    case Options{frames,jar,settings,item_table} Some{value}: Done{Options{Some{U32.to_nat(value)},jar,settings,item_table}}

def numeric(options:Options,field:U32,value:Maybe<&2,U32>) -> Result<&2,&2,String,Options>:
  match options value:
    case _ None{}: Fail{"presentation settings require unsigned integers"}
    case Options{frames,jar,settings,item_table} Some{number}: Done{Options{frames,jar,Presentation.setting(settings,field,number),item_table}}

type Token is Data:
  Frames{}
  Jar{}
  ItemTable{}
  Width{}
  Height{}
  RenderScale{}
  HUDScale{}
  DisplayNative{}
  Fullscreen{}
  Windowed{}
  Unknown{}

type Argument is Data:
  Argument{token:Token,text:String}

# Equality classification avoids expansion of long structural string patterns.

def classify_windowed(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Windowed{}
    case False{}: Unknown{}

def classify_fullscreen(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Fullscreen{}
    case False{}: classify_windowed(String.eq(name,"--windowed"),name)

def classify_displaynative(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: DisplayNative{}
    case False{}: classify_fullscreen(String.eq(name,"--fullscreen"),name)

def classify_hudscale(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: HUDScale{}
    case False{}: classify_displaynative(String.eq(name,"--display-native"),name)

def classify_renderscale(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: RenderScale{}
    case False{}: classify_hudscale(String.eq(name,"--hud-scale"),name)

def classify_height(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Height{}
    case False{}: classify_renderscale(String.eq(name,"--render-scale"),name)

def classify_width(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Width{}
    case False{}: classify_height(String.eq(name,"--height"),name)

def classify_itemtable(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: ItemTable{}
    case False{}: classify_width(String.eq(name,"--width"),name)

def classify_jar(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Jar{}
    case False{}: classify_itemtable(String.eq(name,"--item-table"),name)

def classify_frames(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Frames{}
    case False{}: classify_jar(String.eq(name,"--jar"),name)

def token(+name:String) -> Token:
  classify_frames(String.eq(name,"--frames"),name)

def arguments(args:List<String>) -> List<Argument>:
  match args:
    case Nil{}: []
    case +name <> rest: Argument{token(name),name} <> arguments(rest)

def parse_arguments(args:List<Argument>,options:Options) -> Result<&2,&2,String,Options>:
  match args options:
    case Nil{} _: Done{options}
    case Argument{Frames{},name} <> Argument{value_token,value} <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- count(options,U32.read(value))
        parse_arguments(rest,next)
    case Argument{Jar{},name} <> Argument{value_token,value} <> rest Options{frames,jar,settings,item_table}:
      parse_arguments(rest,Options{frames,value,settings,item_table})
    case Argument{ItemTable{},name} <> Argument{value_token,value} <> rest Options{frames,jar,settings,item_table}:
      parse_arguments(rest,Options{frames,jar,settings,value})
    case Argument{Width{},name} <> Argument{value_token,value} <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- numeric(options,0,U32.read(value))
        parse_arguments(rest,next)
    case Argument{Height{},name} <> Argument{value_token,value} <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- numeric(options,1,U32.read(value))
        parse_arguments(rest,next)
    case Argument{RenderScale{},name} <> Argument{value_token,value} <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- numeric(options,2,U32.read(value))
        parse_arguments(rest,next)
    case Argument{HUDScale{},name} <> Argument{value_token,value} <> rest _:
      do Result<&2,&2,String,Options>:
        next : Options <- numeric(options,3,U32.read(value))
        parse_arguments(rest,next)
    case Argument{DisplayNative{},name} <> rest Options{frames,jar,Presentation.Settings{width,height,percent,scale,native,fullscreen},item_table}:
      parse_arguments(rest,Options{frames,jar,Presentation.Settings{width,height,percent,scale,True{},fullscreen},item_table})
    case Argument{Fullscreen{},name} <> rest Options{frames,jar,Presentation.Settings{width,height,percent,scale,native,fullscreen},item_table}:
      parse_arguments(rest,Options{frames,jar,Presentation.Settings{width,height,percent,scale,native,True{}},item_table})
    case Argument{Windowed{},name} <> rest Options{frames,jar,Presentation.Settings{width,height,percent,scale,native,fullscreen},item_table}:
      parse_arguments(rest,Options{frames,jar,Presentation.Settings{width,height,percent,scale,native,False{}},item_table})
    case Argument{value_token,name} <> rest _: Fail{"unknown/incomplete option " ++ name}

def parse(args:List<String>,options:Options) -> Result<&2,&2,String,Options>:
  parse_arguments(arguments(args),options)
