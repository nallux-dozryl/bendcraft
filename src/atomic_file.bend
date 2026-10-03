import Base
import ./durability.bend as D

type Stage is Data:
  Created{}
  Written{}
  Synced{}
  Published{}
  DirectorySynced{}

type Outcome is Data:
  Durable{}
  NotPublished{code: U32, message: String}
  PublishedUnsynced{code: U32, message: String}

def stage_name(stage: Stage) -> String:
  match stage:
    case Created{}: "created"
    case Written{}: "written"
    case Synced{}: "synced"
    case Published{}: "published"
    case DirectorySynced{}: "directory_synced"

def outcome_text(outcome: Outcome) -> String:
  match outcome:
    case Durable{}: "durable"
    case NotPublished{code, message}: "not_published:" ++ U32.show(code) ++ ":" ++ message
    case PublishedUnsynced{code, message}: "published_unsynced:" ++ U32.show(code) ++ ":" ++ message

def parent_parts(parts: List<&2, String>, prefix: String) -> String:
  match parts:
    case Nil{}: "."
    case last <> Nil{}: prefix
    case head <> rest: parent_parts(rest, prefix ++ head ++ "/")

def nonempty_parent(parent: String) -> String:
  match parent:
    case SNil{}: "."
    case other: other

def parent(path: String) -> String:
  nonempty_parent(parent_parts(String.split(path, '/'), ""))

def suffix_chars(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c}, rest}:
      ((U32.is_ge(c, 48) && U32.is_le(c, 57)) || (U32.is_ge(c, 97) && U32.is_le(c, 122)) || U32.is_eq(c, 45)) && suffix_chars(rest)

def suffix_within(fuel: Nat, text: String) -> Bool:
  match fuel text:
    case _ SNil{}: True{}
    case 0n _: False{}
    case 1n+n SCon{c, rest}: suffix_within(n, rest)

def valid_suffix(+suffix: String) -> Bool:
  Bool.not(String.is_empty(suffix)) && suffix_within(64n, suffix) && suffix_chars(suffix)

def cleanup_done(original: U32 & String, removed: Result<&1, &1, U32 & String, Unit>) -> Outcome:
  (code, message) = original
  match removed:
    case Done{u}: NotPublished{code, message}
    case Fail{error}: NotPublished{code, message ++ "; temporary cleanup failed"}

def cleanup(temp: String, original: U32 & String) -> IO(Outcome):
  do IO<Outcome>:
    removed : Result<&1, &1, U32 & String, Unit> <- D.Durability.remove(temp)
    return cleanup_done(original, removed)

def directory_result(~hook: Stage -> IO(Unit), result: Result<&1, &1, U32 & String, Unit>) -> IO(Outcome):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Outcome, PublishedUnsynced{code, message})
    case Done{u}:
      do IO<Outcome>:
        hook(DirectorySynced{})
        return Durable{}

def renamed(~hook: Stage -> IO(Unit), result: Result<&1, &1, U32 & String, Unit>, temp: String, directory: String) -> IO(Outcome):
  match result:
    case Fail{error}: cleanup(temp, error)
    case Done{u}:
      do IO<Outcome>:
        hook(Published{})
        synced : Result<&1, &1, U32 & String, Unit> <- D.Durability.sync_directory(directory)
        directory_result(~hook, synced)

def synced(~hook: Stage -> IO(Unit), result: File & Result<&1, &1, U32 & String, Unit>, +temp: String, path: String, directory: String) -> IO(Outcome):
  (file, status) = result
  match status:
    case Fail{error}:
      do IO<Outcome>:
        File.close(file)
        cleanup(temp, error)
    case Done{u}:
      do IO<Outcome>:
        hook(Synced{})
        File.close(file)
        moved : Result<&1, &1, U32 & String, Unit> <- D.Durability.replace(temp, path)
        renamed(~hook, moved, temp, directory)

def written(~hook: Stage -> IO(Unit), result: File & Result<&1, &1, U32 & String, Unit>, temp: String, path: String, directory: String) -> IO(Outcome):
  (file, status) = result
  match status:
    case Fail{error}:
      do IO<Outcome>:
        File.close(file)
        cleanup(temp, error)
    case Done{u}:
      do IO<Outcome>:
        hook(Written{})
        result : File & Result<&1, &1, U32 & String, Unit> <- D.Durability.sync(file)
        synced(~hook, result, temp, path, directory)

def created(~hook: Stage -> IO(Unit), result: Result<&1, &1, U32 & String, File>, temp: String, path: String, directory: String, bytes: List<&2, U32>) -> IO(Outcome):
  match result:
    case Fail{Tuple{code, message}}: IO.pure(Outcome, NotPublished{code, message})
    case Done{file}:
      do IO<Outcome>:
        hook(Created{})
        result : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, bytes)
        written(~hook, result, temp, path, directory)

def publish_valid(~hook: Stage -> IO(Unit), valid: Bool, +path: String, suffix: String, bytes: List<&2, U32>) -> IO(Outcome):
  match valid:
    case False{}: IO.pure(Outcome, NotPublished{22, "temporary suffix must contain 1..64 lowercase letters, digits or hyphens"})
    case True{}:
      do IO<Outcome>:
        +temp : String = path ++ ".pending-" ++ suffix
        result : Result<&1, &1, U32 & String, File> <- D.Durability.create(temp)
        created(~hook, result, temp, path, parent(path), bytes)

# Hooks exist for interruption tests and optional caller observation. Production
# callers normally use publish; no stage hook is part of the persisted format.
def publish_with(~hook: Stage -> IO(Unit), path: String, +suffix: String, bytes: List<&2, U32>) -> IO(Outcome):
  publish_valid(~hook, valid_suffix(suffix), path, suffix, bytes)

def quiet(stage: Stage) -> IO(Unit):
  IO.pure(Unit, Unit{})

def publish(path: String, suffix: String, bytes: List<&2, U32>) -> IO(Outcome):
  publish_with(~quiet, path, suffix, bytes)
