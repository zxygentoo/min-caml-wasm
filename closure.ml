type closure = { entry : Id.l; actual_fv : Id.t list }

type t =
  | Unit
  | Int of int
  | Float of float
  | Neg of Id.t
  | Add of Id.t * Id.t
  | Sub of Id.t * Id.t
  | FNeg of Id.t
  | FAdd of Id.t * Id.t
  | FSub of Id.t * Id.t
  | FMul of Id.t * Id.t
  | FDiv of Id.t * Id.t
  | IfEq of Id.t * Id.t * t * t
  | IfLE of Id.t * Id.t * t * t
  | Let of (Id.t * Type.t) * t * t
  | Var of Id.t
  | MakeCls of (Id.t * Type.t) * closure * t
  | AppCls of Id.t * Id.t list
  | AppDir of Id.l * Id.t list
  | Tuple of Id.t list
  | LetTuple of (Id.t * Type.t) list * Id.t * t
  | Get of Id.t * Id.t
  | Put of Id.t * Id.t * Id.t
  | ExtArray of Id.l

type fundef = { name : Id.l * Type.t;
                args : (Id.t * Type.t) list;
                formal_fv : (Id.t * Type.t) list;
                body : t }

type prog = Prog of fundef list * t

let rec fv = function
  | Unit | Int(_) | Float(_) | ExtArray(_) -> S.empty
  | Neg(x) | FNeg(x) -> S.singleton x
  | Add(x, y) | Sub(x, y)
  | FAdd(x, y) | FSub(x, y) | FMul(x, y) | FDiv(x, y)
  | Get(x, y) -> S.of_list [x; y]
  | IfEq(x, y, e1, e2)| IfLE(x, y, e1, e2) ->
    S.add x (S.add y (S.union (fv e1) (fv e2)))
  | Let((x, _t), e1, e2) -> S.union (fv e1) (S.remove x (fv e2))
  | Var(x) -> S.singleton x
  | MakeCls((x, _t), { entry = _; actual_fv = ys }, e) ->
    S.remove x (S.union (S.of_list ys) (fv e))
  | AppCls(x, ys) -> S.of_list (x :: ys)
  | AppDir(_, xs) | Tuple(xs) -> S.of_list xs
  | LetTuple(xts, y, e) ->
    S.add y (S.diff (fv e) (S.of_list (List.map fst xts)))
  | Put(x, y, z) -> S.of_list [x; y; z]

let toplevel : fundef list ref = ref []

let rec g env known = function
  | Knormal.Unit -> Unit
  | Knormal.Int(i) -> Int(i)
  | Knormal.Float(d) -> Float(d)
  | Knormal.Neg(x) -> Neg(x)
  | Knormal.Add(x, y) -> Add(x, y)
  | Knormal.Sub(x, y) -> Sub(x, y)
  | Knormal.FNeg(x) -> FNeg(x)
  | Knormal.FAdd(x, y) -> FAdd(x, y)
  | Knormal.FSub(x, y) -> FSub(x, y)
  | Knormal.FMul(x, y) -> FMul(x, y)
  | Knormal.FDiv(x, y) -> FDiv(x, y)
  | Knormal.IfEq(x, y, e1, e2) -> IfEq(x, y, g env known e1, g env known e2)
  | Knormal.IfLE(x, y, e1, e2) -> IfLE(x, y, g env known e1, g env known e2)
  | Knormal.Let((x, t), e1, e2) ->
    Let((x, t), g env known e1, g (M.add x t env) known e2)
  | Knormal.Var(x) -> Var(x)
  | Knormal.LetRec(
      { Knormal.name = (x, t); Knormal.args = yts; Knormal.body = e1 }, e2
    ) ->
    let toplevel_backup = !toplevel in
    let env' = M.add x t env in
    let known' = S.add x known in
    let e1' = g (M.add_list yts env') known' e1 in
    let zs = S.diff (fv e1') (S.of_list (List.map fst yts)) in
    let known', e1' =
      if S.is_empty zs then known', e1' else
        (Format.eprintf "free variable(s) %s found in function %s@."
           (Id.pp_list (S.elements zs)) x;
         Format.eprintf "function %s cannot be directly applied in fact@." x;
         toplevel := toplevel_backup;
         let e1' = g (M.add_list yts env') known e1 in
         known, e1') in
    let zs = 
      S.elements (S.diff (fv e1') (S.add x (S.of_list (List.map fst yts))))
    in
    let zts = List.map (fun z -> (z, M.find z env')) zs in
    toplevel := {
      name = (Id.L(x), t); args = yts; formal_fv = zts; body = e1'
    } :: !toplevel;
    let e2' = g env' known' e2 in
    if S.mem x (fv e2') then
      MakeCls((x, t), { entry = Id.L(x); actual_fv = zs }, e2')
    else
      (Format.eprintf "eliminating closure(s) %s@." x; e2')
  | Knormal.App(x, ys) when S.mem x known ->
    Format.eprintf "directly applying %s@." x;
    AppDir(Id.L(x), ys)
  | Knormal.App(f, xs) -> AppCls(f, xs)
  | Knormal.Tuple(xs) -> Tuple(xs)
  | Knormal.LetTuple(xts, y, e) ->
    LetTuple(xts, y, g (M.add_list xts env) known e)
  | Knormal.Get(x, y) -> Get(x, y)
  | Knormal.Put(x, y, z) -> Put(x, y, z)
  | Knormal.ExtArray(x) -> ExtArray(Id.L(x))
  | Knormal.ExtFunApp(x, ys) -> AppDir(Id.L("min_caml_" ^ x), ys)

let f e =
  toplevel := [];
  let e' = g M.empty S.empty e in
  Prog(List.rev !toplevel, e')
