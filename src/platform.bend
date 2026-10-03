import Base

# Diagnostic effects for automated native launch verification. These are
# foreign observations, not Bend proofs or game behavior implementations.
def Platform.observe() -> IO(String):
  import "./native/platform.c"
  import "./native/platform.js"

def Platform.inspect(window: Window) -> IO(Window & String):
  import "./native/platform.c"
  import "./native/platform.js"
