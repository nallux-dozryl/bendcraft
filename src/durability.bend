import Base

# Base File provides byte IO but no exclusive create, fsync, rename or parent
# directory sync. These are OS effects only; codecs and save policy stay Bend.
def Durability.create(path: String) -> IO(Result<&1, &1, U32 & String, File>):
  import "./native/durability.c"
  import "./native/durability.js"

def Durability.sync(file: File) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "./native/durability.c"
  import "./native/durability.js"

def Durability.replace(source: String, destination: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/durability.c"
  import "./native/durability.js"

def Durability.sync_directory(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/durability.c"
  import "./native/durability.js"

def Durability.remove(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/durability.c"
  import "./native/durability.js"
