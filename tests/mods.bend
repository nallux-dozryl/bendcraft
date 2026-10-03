import Base
import ../src/json.bend as J
import ../src/mods.bend as M

law both_covers:
  for side: M.Side
  {M.covers(M.Both{}, side) == True{} : Bool}

def both_covers(side):
  match side:
    case M.Client{}: {==}
    case M.Server{}: {==}
    case M.Both{}: {==}

def endpoint_fixture() -> Bool:
  +range = {M.Range{Some{M.Bound{M.Version{1, 0, 0}, True{}}}, Some{M.Bound{M.Version{2, 0, 0}, False{}}}} : M.Range}
  M.contains(range, M.Version{1, 0, 0}) && Bool.not(M.contains(range, M.Version{2, 0, 0}))

law range_endpoints:
  {endpoint_fixture() == True{} : Bool}

def range_endpoints():
  {==}

def error(message: String) -> J.Value:
  J.JObject{[J.JMember{"ok", J.JBool{False{}}}, J.JMember{"error", J.JString{message}}]}

def order_result(result: Result<&2, &2, String, List<&2, M.Manifest>>) -> J.Value:
  match result:
    case Fail{message}: error(message)
    case Done{manifests}: J.JObject{[J.JMember{"ok", J.JBool{True{}}}, J.JMember{"order", M.json_strings(M.manifest_ids(manifests))}]}

def resolve_input(parsed: Result<&2, &2, String, J.Value>, side: M.Side) -> Result<&2, &2, String, List<&2, M.Manifest>>:
  do Result<&2, &2, String, List<&2, M.Manifest>>:
    value : J.Value <- parsed
    manifests : List<&2, M.Manifest> <- M.decode_pack(value)
    M.resolve(side, M.Version{1, 0, 0}, manifests)

def matching_inputs(left: Result<&2, &2, String, J.Value>, right: Result<&2, &2, String, J.Value>) -> Result<&2, &2, String, M.MatchReport>:
  do Result<&2, &2, String, M.MatchReport>:
    c : J.Value <- left
    s : J.Value <- right
    client : List<&2, M.Manifest> <- M.decode_pack(c)
    server : List<&2, M.Manifest> <- M.decode_pack(s)
    M.match_sides(client, server, M.Version{1, 0, 0})

def match_result(result: Result<&2, &2, String, M.MatchReport>) -> J.Value:
  match result:
    case Fail{message}: error(message)
    case Done{report}: J.JObject{[J.JMember{"ok", J.JBool{True{}}}, J.JMember{"match", M.match_value(report)}]}

def reloading_inputs(left: Result<&2, &2, String, J.Value>, right: Result<&2, &2, String, J.Value>) -> Result<&2, &2, String, M.ReloadReport>:
  do Result<&2, &2, String, M.ReloadReport>:
    old_value : J.Value <- left
    next_value : J.Value <- right
    old : M.Manifest <- M.decode(old_value)
    next : M.Manifest <- M.decode(next_value)
    return M.classify_reload(old, next)

def reload_result(result: Result<&2, &2, String, M.ReloadReport>) -> J.Value:
  match result:
    case Fail{message}: error(message)
    case Done{report}: J.JObject{[J.JMember{"ok", J.JBool{True{}}}, J.JMember{"reload", M.reload_value(report)}]}

def version_input(parsed: Result<&2, &2, String, J.Value>) -> Result<&2, &2, String, M.Version>:
  do Result<&2, &2, String, M.Version>:
    value : J.Value <- parsed
    M.parse_version(value)

def version_result(result: Result<&2, &2, String, M.Version>) -> J.Value:
  match result:
    case Fail{message}: error(message)
    case Done{version}: J.JObject{[J.JMember{"ok", J.JBool{True{}}}, J.JMember{"version", J.JString{M.version_show(version)}}]}

def run_case(mode: String, a: String, b: String) -> J.Value:
  match mode:
    case "client": order_result(resolve_input(J.parse(a), M.Client{}))
    case "server": order_result(resolve_input(J.parse(a), M.Server{}))
    case "both": order_result(resolve_input(J.parse(a), M.Both{}))
    case "match": match_result(matching_inputs(J.parse(a), J.parse(b)))
    case "reload": reload_result(reloading_inputs(J.parse(a), J.parse(b)))
    case "version": version_result(version_input(J.parse(a)))
    case _: error("UnknownTestMode")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case mode <> a <> b <> tail:
      do IO<Unit>:
        IO.print(J.encode(run_case(mode, a, b)))
        batch(tail)
    case _: IO.die(Unit, 2, "batch requires MODE JSON_A JSON_B triples")

def main_args(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.print(J.choose(String, "fixtures pass", "fixtures FAIL", endpoint_fixture()))
    case "batch" <> rest: batch(rest)
    case mode <> a <> b <> Nil{}: IO.print(J.encode(run_case(mode, a, b)))
    case _: IO.die(Unit, 2, "usage: mods-tests [MODE JSON_A JSON_B] or [batch TRIPLES...]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    main_args(List.tail(&1, String, args))
