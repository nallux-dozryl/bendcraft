import Base

type Options is Data:
  Options{fixture:Bool,profile:String,creative:Bool,run:Maybe<&2,Bool>,control:Bool,sine:String}

type Token is Data:
  Fixture{}
  WorldProfile{}
  GameMode{}
  Unpaused{}
  Paused{}
  StdinControl{}
  Sine{}
  Creative{}
  Survival{}
  Unknown{}

def defaults() -> Options:
  Options{False{},"bendex:stone-dirt-superflat",True{},None{},False{},"generated/reference_mth_sin.f32"}

def running(options:Options) -> Bool:
  Options{fixture,profile,creative,run,control,sine} = options
  match run:
    case Some{enabled}: enabled
    case None{}: Bool.not(fixture)

# Equality classification keeps long literals out of structural fallback arms.
# Each match scrutinizes a real parameter, as required by Bend.

def classify_survival(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Survival{}
    case False{}: Unknown{}

def classify_creative(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Creative{}
    case False{}: classify_survival(String.eq(name,"survival"),name)

def classify_sine(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Sine{}
    case False{}: classify_creative(String.eq(name,"creative"),name)

def classify_stdincontrol(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: StdinControl{}
    case False{}: classify_sine(String.eq(name,"--sine"),name)

def classify_paused(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Paused{}
    case False{}: classify_stdincontrol(String.eq(name,"--stdin-control"),name)

def classify_unpaused(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Unpaused{}
    case False{}: classify_paused(String.eq(name,"--paused"),name)

def classify_gamemode(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: GameMode{}
    case False{}: classify_unpaused(String.eq(name,"--unpaused"),name)

def classify_worldprofile(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: WorldProfile{}
    case False{}: classify_gamemode(String.eq(name,"--game-mode"),name)

def classify_fixture(valid:Bool,+name:String) -> Token:
  match valid:
    case True{}: Fixture{}
    case False{}: classify_worldprofile(String.eq(name,"--world-profile"),name)

def token(+name:String) -> Token:
  classify_fixture(String.eq(name,"--verification-fixture"),name)

type Argument is Data:
  Argument{token:Token,text:String}

def arguments(args:List<String>) -> List<Argument>:
  match args:
    case Nil{}: Nil{}
    case +name <> rest: Argument{token(name),name} <> arguments(rest)

def parse_arguments(args:List<Argument>,options:Options) -> Result<&2,&2,String,Options>:
  match args options:
    case Nil{} _: Done{options}
    case Argument{Fixture{},name} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{True{},profile,creative,run,control,sine})
    case Argument{WorldProfile{},name} <> Argument{value_token,value} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,value,creative,run,control,sine})
    case Argument{GameMode{},name} <> Argument{Creative{},value} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,profile,True{},run,control,sine})
    case Argument{GameMode{},name} <> Argument{Survival{},value} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,profile,False{},run,control,sine})
    case Argument{Unpaused{},name} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,profile,creative,Some{True{}},control,sine})
    case Argument{Paused{},name} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,profile,creative,Some{False{}},control,sine})
    case Argument{StdinControl{},name} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,profile,creative,run,True{},sine})
    case Argument{Sine{},name} <> Argument{value_token,value} <> rest Options{fixture,profile,creative,run,control,sine}:
      parse_arguments(rest,Options{fixture,profile,creative,run,control,value})
    case Argument{value_token,name} <> rest _: Fail{"unknown/incomplete option " ++ name}

def parse(args:List<String>,options:Options) -> Result<&2,&2,String,Options>:
  parse_arguments(arguments(args),options)

def validated_profile(valid:Bool,options:Options) -> Result<&2,&2,String,Options>:
  match valid options:
    case True{} _: Done{options}
    case False{} Options{fixture,profile,creative,run,control,sine}:
      Fail{"unsupported world profile " ++ profile}

def validate(result:Result<&2,&2,String,Options>) -> Result<&2,&2,String,Options>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Options{False{},+profile,creative,run,control,sine}}:
      validated_profile(String.eq(profile,"bendex:stone-dirt-superflat"),Options{False{},profile,creative,run,control,sine})
    case Done{options}: Done{options}
