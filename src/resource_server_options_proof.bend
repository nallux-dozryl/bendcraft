import Base
import ./resource_server_options.bend as CLI

import ./resource_server_options_laws.bend as Laws

def Laws.empty_arguments_preserve_complete_options(options):
  {==}

def Laws.fixture_step(tail,fixture,profile,creative,run,control,sine):
  {==}

def Laws.profile_step(tail,fixture,profile,creative,run,control,sine,value):
  {==}

def Laws.creative_step(tail,fixture,profile,creative,run,control,sine):
  {==}

def Laws.survival_step(tail,fixture,profile,creative,run,control,sine):
  {==}

def Laws.unpaused_step(tail,fixture,profile,creative,run,control,sine):
  {==}

def Laws.paused_step(tail,fixture,profile,creative,run,control,sine):
  {==}

def Laws.control_step(tail,fixture,profile,creative,run,control,sine):
  {==}

def Laws.sine_step(tail,fixture,profile,creative,run,control,sine,value):
  {==}

def Laws.missing_profile_value(options):
  {==}

def Laws.missing_mode_value(options):
  {==}

def Laws.missing_sine_value(options):
  {==}

def Laws.parser_failure_is_retained(message):
  {==}

def Laws.fixture_accepts_complete_options(profile,creative,run,control,sine):
  {==}

def Laws.accepted_profile(profile,creative,run,control,sine,admitted):
  %Equal.sym(Bool,String.eq(profile,"bendex:stone-dirt-superflat"),True{},admitted) :
    {CLI.validated_profile(_,CLI.Options{False{},profile,creative,run,control,sine}) == Done{CLI.Options{False{},profile,creative,run,control,sine}} : Result<&2,&2,String,CLI.Options>}
  {==}

def Laws.unsupported_profile(profile,creative,run,control,sine,admitted):
  %Equal.sym(Bool,String.eq(profile,"bendex:stone-dirt-superflat"),False{},admitted) :
    {CLI.validated_profile(_,CLI.Options{False{},profile,creative,run,control,sine}) == Fail{"unsupported world profile " ++ profile} : Result<&2,&2,String,CLI.Options>}
  {==}

def Laws.explicit_run_is_retained(fixture,profile,creative,run,control,sine,enabled):
  {==}

def Laws.fixture_defaults_to_paused(fixture,profile,creative,run,control,sine):
  {==}

def Laws.ordinary_defaults_to_running(fixture,profile,creative,run,control,sine):
  {==}

