import Base
import ../src/atomic_file.bend as A

def pause_if(valid: Bool) -> IO(Unit):
  match valid:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.sleep(30000)

def stage_config(value: Result<&1, &1, U32 & String, String>) -> String:
  match value:
    case Fail{error}: ""
    case Done{name}: name

def observe_inner(+stage: A.Stage) -> IO(Unit):
  do IO<Unit>:
    IO.print(A.stage_name(stage))
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("MC_ATOMIC_PAUSE")
    pause_if(String.eq(stage_config(env), A.stage_name(stage)))

def observe(stage: A.Stage) -> IO(Unit):
  observe_inner(stage)

def payload(mode: String) -> List<&2, U32>:
  match mode:
    case "invalid": [65, 256, 66]
    case "empty": []
    case _: [0, 1, 2, 255, 77, 105, 110, 101, 99, 114, 97, 102, 116, 10]

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case exe <> path <> suffix <> mode <> Nil{}:
      do IO<Unit>:
        outcome : A.Outcome <- A.publish_with(~observe, path, suffix, payload(mode))
        IO.print(A.outcome_text(outcome))
    case _: IO.die(Unit, 1, "expected path suffix mode")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
