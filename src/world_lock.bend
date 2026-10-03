import Base

# The pinned compiler supports only Base handle laws. Wrap an owned File
# descriptor rather than inventing an unchecked user handle law.
type Lease is Type:
  Lease{file: File}

def Native.acquire(path: String) -> IO(Result<&1, &1, U32 & String, File>):
  import "./native/world_lock.c"
  import "./native/world_lock.js"

def Native.release(file: File) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/world_lock.c"
  import "./native/world_lock.js"

def packed(result: Result<&1, &1, U32 & String, File>) -> Result<&1, &1, U32 & String, Lease>:
  match result:
    case Fail{error}: Fail{error}
    case Done{file}: Done{Lease{file}}

def acquire(path: String) -> IO(Result<&1, &1, U32 & String, Lease>):
  do IO<Result<&1, &1, U32 & String, Lease>>:
    result : Result<&1, &1, U32 & String, File> <- Native.acquire(path)
    return packed(result)

def release(lease: Lease) -> IO(Result<&1, &1, U32 & String, Unit>):
  Lease{file} = lease
  Native.release(file)
