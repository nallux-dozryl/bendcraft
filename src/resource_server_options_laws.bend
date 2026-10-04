import Base
import ./resource_server_options.bend as CLI

law empty_arguments_preserve_complete_options:
  for +options:CLI.Options
  {CLI.parse([],options) == Done{options} : Result<&2,&2,String,CLI.Options>}

law fixture_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.parse("--verification-fixture" <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{True{},profile,creative,run,control,sine}) : Result<&2,&2,String,CLI.Options>}

law profile_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  for +value:String
  {CLI.parse("--world-profile" <> value <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,value,creative,run,control,sine}) : Result<&2,&2,String,CLI.Options>}

law creative_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.parse("--game-mode" <> "creative" <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,profile,True{},run,control,sine}) : Result<&2,&2,String,CLI.Options>}

law survival_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.parse("--game-mode" <> "survival" <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,profile,False{},run,control,sine}) : Result<&2,&2,String,CLI.Options>}

law unpaused_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.parse("--unpaused" <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,profile,creative,Some{True{}},control,sine}) : Result<&2,&2,String,CLI.Options>}

law paused_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.parse("--paused" <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,profile,creative,Some{False{}},control,sine}) : Result<&2,&2,String,CLI.Options>}

law control_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.parse("--stdin-control" <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,profile,creative,run,True{},sine}) : Result<&2,&2,String,CLI.Options>}

law sine_step:
  for tail:List<String>
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  for +value:String
  {CLI.parse("--sine" <> value <> tail,CLI.Options{fixture,profile,creative,run,control,sine}) == CLI.parse(tail,CLI.Options{fixture,profile,creative,run,control,value}) : Result<&2,&2,String,CLI.Options>}

law missing_profile_value:
  for +options:CLI.Options
  {CLI.parse(["--world-profile"],options) == Fail{"unknown/incomplete option --world-profile"} : Result<&2,&2,String,CLI.Options>}

law missing_mode_value:
  for +options:CLI.Options
  {CLI.parse(["--game-mode"],options) == Fail{"unknown/incomplete option --game-mode"} : Result<&2,&2,String,CLI.Options>}

law missing_sine_value:
  for +options:CLI.Options
  {CLI.parse(["--sine"],options) == Fail{"unknown/incomplete option --sine"} : Result<&2,&2,String,CLI.Options>}

law parser_failure_is_retained:
  for +message:String
  {CLI.validate(Fail{message}) == Fail{message} : Result<&2,&2,String,CLI.Options>}

law fixture_accepts_complete_options:
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.validate(Done{CLI.Options{True{},profile,creative,run,control,sine}}) == Done{CLI.Options{True{},profile,creative,run,control,sine}} : Result<&2,&2,String,CLI.Options>}

law accepted_profile:
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  for +admitted:{String.eq(profile,"bendex:stone-dirt-superflat") == True{} : Bool}
  {CLI.validate(Done{CLI.Options{False{},profile,creative,run,control,sine}}) == Done{CLI.Options{False{},profile,creative,run,control,sine}} : Result<&2,&2,String,CLI.Options>}

law unsupported_profile:
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  for +admitted:{String.eq(profile,"bendex:stone-dirt-superflat") == False{} : Bool}
  {CLI.validate(Done{CLI.Options{False{},profile,creative,run,control,sine}}) == Fail{"unsupported world profile " ++ profile} : Result<&2,&2,String,CLI.Options>}

law explicit_run_is_retained:
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  for +enabled:Bool
  {CLI.running(CLI.Options{fixture,profile,creative,Some{enabled},control,sine}) == enabled : Bool}

law fixture_defaults_to_paused:
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.running(CLI.Options{True{},profile,creative,None{},control,sine}) == False{} : Bool}

law ordinary_defaults_to_running:
  for +fixture:Bool
  for +profile:String
  for +creative:Bool
  for +run:Maybe<&2,Bool>
  for +control:Bool
  for +sine:String
  {CLI.running(CLI.Options{False{},profile,creative,None{},control,sine}) == True{} : Bool}

