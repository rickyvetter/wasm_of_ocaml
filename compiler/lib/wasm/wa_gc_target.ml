open! Stdlib
module W = Wa_ast
open Wa_code_generation

type expression = Wa_ast.expression Wa_code_generation.t

module Type = struct
  let value = W.Ref { nullable = false; typ = Eq }

  let block_type =
    register_type "block" (fun () ->
        return
          { supertype = None
          ; final = true
          ; typ = W.Array { mut = true; typ = Value value }
          })

  let string_type =
    register_type "string" (fun () ->
        return
          { supertype = None
          ; final = true
          ; typ = W.Array { mut = true; typ = Packed I8 }
          })

  let float_type =
    register_type "float" (fun () ->
        return
          { supertype = None
          ; final = true
          ; typ = W.Struct [ { mut = true; typ = Value F64 } ]
          })

  let int64_type =
    register_type "int64" (fun () ->
        return
          { supertype = None
          ; final = true
          ; typ = W.Struct [ { mut = true; typ = Value I64 } ]
          })

  let func_type n =
    { W.params = List.init ~len:(n + 1) ~f:(fun _ -> value); result = [ value ] }

  let function_type n =
    register_type (Printf.sprintf "function_%d" n) (fun () ->
        return { supertype = None; final = true; typ = W.Func (func_type n) })

  let closure_type_1 =
    register_type "closure" (fun () ->
        let* fun_ty = function_type 1 in
        return
          { supertype = None
          ; final = false
          ; typ =
              W.Struct
                [ { mut = false; typ = Value I32 }
                ; { mut = false
                  ; typ = Value (Ref { nullable = false; typ = Type fun_ty })
                  }
                ]
          })

  let closure_type arity =
    if arity = 1
    then closure_type_1
    else
      register_type (Printf.sprintf "closure_%d" arity) (fun () ->
          let* cl_typ = closure_type_1 in
          let* fun_ty = function_type 1 in
          let* fun_ty' = function_type arity in
          return
            { supertype = Some cl_typ
            ; final = false
            ; typ =
                W.Struct
                  [ { mut = false; typ = Value I32 }
                  ; { mut = false
                    ; typ = Value (Ref { nullable = false; typ = Type fun_ty })
                    }
                  ; { mut = false
                    ; typ = Value (Ref { nullable = false; typ = Type fun_ty' })
                    }
                  ]
            })

  let env_type ~arity n =
    register_type (Printf.sprintf "env_%d_%d" arity n) (fun () ->
        let* cl_typ = closure_type arity in
        let* fun_ty = function_type 1 in
        let* fun_ty' = function_type arity in
        return
          { supertype = Some cl_typ
          ; final = true
          ; typ =
              W.Struct
                ((if arity = 1
                  then
                    [ { W.mut = false; typ = W.Value I32 }
                    ; { mut = false
                      ; typ = Value (Ref { nullable = false; typ = Type fun_ty })
                      }
                    ]
                  else
                    [ { mut = false; typ = Value I32 }
                    ; { mut = false
                      ; typ = Value (Ref { nullable = false; typ = Type fun_ty })
                      }
                    ; { mut = false
                      ; typ = Value (Ref { nullable = false; typ = Type fun_ty' })
                      }
                    ])
                @ List.init
                    ~f:(fun _ ->
                      { W.mut = false
                      ; typ = W.Value (Ref { nullable = false; typ = Eq })
                      })
                    ~len:n)
          })

  let rec_env_type ~function_count ~free_variable_count =
    register_type
      (Printf.sprintf "rec_env_%d_%d" function_count free_variable_count)
      (fun () ->
        return
          { supertype = None
          ; final = true
          ; typ =
              W.Struct
                (List.init
                   ~f:(fun i ->
                     { W.mut = i < function_count
                     ; typ = W.Value (Ref { nullable = false; typ = Eq })
                     })
                   ~len:(function_count + free_variable_count))
          })

  let rec_closure_type ~arity ~function_count ~free_variable_count =
    register_type
      (Printf.sprintf "closure_rec_%d_%d_%d" arity function_count free_variable_count)
      (fun () ->
        let* cl_typ = closure_type arity in
        let* fun_ty = function_type 1 in
        let* fun_ty' = function_type arity in
        let* env_ty = rec_env_type ~function_count ~free_variable_count in
        return
          { supertype = Some cl_typ
          ; final = true
          ; typ =
              W.Struct
                ((if arity = 1
                  then
                    [ { W.mut = false; typ = W.Value I32 }
                    ; { mut = false
                      ; typ = Value (Ref { nullable = false; typ = Type fun_ty' })
                      }
                    ]
                  else
                    [ { mut = false; typ = Value I32 }
                    ; { mut = false
                      ; typ = Value (Ref { nullable = false; typ = Type fun_ty })
                      }
                    ; { mut = false
                      ; typ = Value (Ref { nullable = false; typ = Type fun_ty' })
                      }
                    ])
                @ [ { W.mut = false
                    ; typ = W.Value (Ref { nullable = false; typ = Type env_ty })
                    }
                  ])
          })

  let rec curry_type arity m =
    register_type (Printf.sprintf "curry_%d_%d" arity m) (fun () ->
        let* cl_typ = closure_type 1 in
        let* fun_ty = function_type 1 in
        let* cl_ty = if m = arity then closure_type arity else curry_type arity (m + 1) in
        return
          { supertype = Some cl_typ
          ; final = true
          ; typ =
              W.Struct
                [ { W.mut = false; typ = W.Value I32 }
                ; { mut = false
                  ; typ = Value (Ref { nullable = false; typ = Type fun_ty })
                  }
                ; { mut = false
                  ; typ = Value (Ref { nullable = false; typ = Type cl_ty })
                  }
                ; { W.mut = false; typ = Value value }
                ]
          })
end

module Value = struct
  let value = Type.value

  let unit = return (W.I31New (Const (I32 0l)))

  let val_int = Arith.to_int31

  let int_val i = Arith.of_int31 (cast I31 i)

  let check_is_not_zero i =
    let* i = i in
    return (W.UnOp (I32 Eqz, RefEq (i, W.I31New (Const (I32 0l)))))

  let check_is_int i =
    let* i = i in
    return (W.RefTest ({ nullable = false; typ = I31 }, i))

  let not = Arith.eqz

  let binop op i i' = val_int (op (int_val i) (int_val i'))

  let lt = binop Arith.( < )

  let le = binop Arith.( <= )

  let eq i i' =
    let* i = i in
    let* i' = i' in
    val_int (return (W.RefEq (i, i')))

  let neq i i' =
    let* i = i in
    let* i' = i' in
    val_int (Arith.eqz (return (W.RefEq (i, i'))))

  let ult = binop Arith.(ult)

  let is_int i =
    let* i = i in
    val_int (return (W.RefTest ({ nullable = false; typ = I31 }, i)))

  let int_add = binop Arith.( + )

  let int_sub = binop Arith.( - )

  let int_mul = binop Arith.( * )

  let int_neg i = val_int Arith.(const 0l - int_val i)

  let int_or = binop Arith.( lor )

  let int_and = binop Arith.( land )

  let int_xor = binop Arith.( lxor )

  let int_lsl = binop Arith.( lsl )

  let int_lsr = binop Arith.( lsr )

  let int_asr = binop Arith.( asr )
end

module Memory = struct
  let allocate _ _ ~tag l =
    let* l =
      expression_list
        (fun v ->
          match v with
          | `Var y -> load y
          | `Expr e -> return e)
        l
    in
    let* ty = Type.block_type in
    return (W.ArrayNewFixed (ty, I31New (Const (I32 (Int32.of_int tag))) :: l))
  (*ZZZ Float array?*)

  let wasm_cast ty e =
    let* e = e in
    return (W.RefCast ({ nullable = false; typ = Type ty }, e))

  let wasm_struct_get ty e i =
    let* e = e in
    match e with
    | W.RefCast (_, GlobalGet nm) -> (
        let* init = get_global nm in
        match init with
        | Some (W.StructNew (_, l)) ->
            let e = List.nth l i in
            let* b = is_small_constant e in
            if b then return e else return (W.StructGet (None, ty, i, e))
        | _ -> return (W.StructGet (None, ty, i, e)))
    | _ -> return (W.StructGet (None, ty, i, e))

  let wasm_struct_set ty e i e' =
    let* e = e in
    let* e' = e' in
    instr (W.StructSet (None, ty, i, e, e'))

  let wasm_array_get ?(ty = Type.block_type) e e' =
    let* ty = ty in
    let* e = wasm_cast ty e in
    let* e' = e' in
    return (W.ArrayGet (None, ty, e, e'))

  let wasm_array_set ?(ty = Type.block_type) e e' e'' =
    let* ty = ty in
    let* e = wasm_cast ty e in
    let* e' = e' in
    let* e'' = e'' in
    instr (W.ArraySet (None, ty, e, e', e''))

  let tag e = wasm_array_get e (Arith.const 0l)

  let block_length e =
    let* e = e in
    Value.int_val (return (W.ArrayLength e))

  let array_get e e' = wasm_array_get e Arith.(Value.int_val e' + const 1l)

  let array_set e e' e'' = wasm_array_set e Arith.(Value.int_val e' + const 1l) e''

  let bytes_get e e' = wasm_array_get ~ty:Type.string_type e (Value.int_val e')

  let bytes_set e e' e'' = wasm_array_set ~ty:Type.string_type e (Value.int_val e') e''

  let field e idx = wasm_array_get e (Arith.const (Int32.of_int (idx + 1)))

  let set_field e idx e' = wasm_array_set e (Arith.const (Int32.of_int (idx + 1))) e'

  let load_function_pointer ~arity closure =
    let* ty = Type.closure_type arity in
    let* fun_ty = Type.function_type arity in
    let* e = wasm_struct_get ty (wasm_cast ty closure) (if arity = 1 then 1 else 2) in
    return (`Ref fun_ty, e)

  let load_function_arity closure =
    let* ty = Type.closure_type_1 in
    wasm_struct_get ty (wasm_cast ty closure) 0
end

module Constant = struct
  let rec translate_rec c =
    match c with
    | Code.Int i -> return (W.I31New (Const (I32 i))) (*ZZZ 32 bit integers *)
    | Tuple (tag, a, _) ->
        let* ty = Type.block_type in
        let* l =
          Array.fold_left
            ~f:(fun prev c ->
              let* acc = prev in
              let* c = translate_rec c in
              return (c :: acc))
            ~init:(return [])
            a
        in
        return (W.ArrayNewFixed (ty, I31New (Const (I32 (Int32.of_int tag))) :: l))
    | NativeString (Byte s | Utf (Utf8 s)) | String s ->
        let* ty = Type.string_type in
        (*ZZZ Use this for long strings
          let name = Code.Var.fresh_n "string" in
          let* () = register_data_segment name [ DataBytes s ] in
          return
            (W.ArrayNewData
               (ty, name, Const (I32 0l), Const (I32 (Int32.of_int (String.length s)))))
        *)
        let l =
          String.fold_right
            ~f:(fun c r -> W.Const (I32 (Int32.of_int (Char.code c))) :: r)
            s
            ~init:[]
        in
        return (W.ArrayNewFixed (ty, l))
    | Float f ->
        let* ty = Type.float_type in
        return (W.StructNew (ty, [ Const (F64 f) ]))
    | Float_array l ->
        let l = Array.to_list l in
        let* bl_ty = Type.block_type in
        let* ty = Type.float_type in
        (*ZZZ Boxed array? *)
        return
          (W.ArrayNewFixed
             ( bl_ty
             , I31New (Const (I32 (Int32.of_int Obj.double_array_tag)))
               :: List.map ~f:(fun f -> W.StructNew (ty, [ Const (F64 f) ])) l ))
    | Int64 i ->
        let* ty = Type.int64_type in
        return (W.StructNew (ty, [ Const (I64 i) ]))

  let translate c =
    let* c = translate_rec c in
    let* b = is_small_constant c in
    if b
    then return c
    else
      let name = Code.Var.fresh_n "const" in
      let* () = register_global (V name) { mut = false; typ = Type.value } c in
      return (W.GlobalGet (V name))
end

module Closure = struct
  let get_free_variables ~context info =
    List.filter
      ~f:(fun x -> not (Hashtbl.mem context.constants x))
      info.Wa_closure_conversion.free_variables

  let rec is_last_fun l f =
    match l with
    | [] -> false
    | [ (g, _) ] -> Code.Var.equal f g
    | _ :: r -> is_last_fun r f

  let translate ~context ~closures ~stack_ctx:_ f =
    let info = Code.Var.Map.find f closures in
    let free_variables = get_free_variables ~context info in
    let arity = List.assoc f info.functions in
    let* curry_fun = if arity > 1 then need_curry_fun ~arity else return f in
    if List.is_empty free_variables
    then
      let* typ = Type.closure_type arity in
      let name = Code.Var.fresh_n "closure" in
      let* () =
        register_global
          (V name)
          { mut = false; typ = Type.value }
          (W.StructNew
             ( typ
             , if arity = 1
               then [ Const (I32 1l); RefFunc (V f) ]
               else
                 [ Const (I32 (Int32.of_int arity))
                 ; RefFunc (V curry_fun)
                 ; RefFunc (V f)
                 ] ))
      in
      return (W.GlobalGet (V name))
    else
      let free_variable_count = List.length free_variables in
      match info.Wa_closure_conversion.functions with
      | [] -> assert false
      | [ _ ] ->
          let* typ = Type.env_type ~arity free_variable_count in
          let* l = expression_list load free_variables in
          return
            (W.StructNew
               ( typ
               , (if arity = 1
                  then [ W.Const (I32 1l); RefFunc (V f) ]
                  else
                    [ Const (I32 (Int32.of_int arity))
                    ; RefFunc (V curry_fun)
                    ; RefFunc (V f)
                    ])
                 @ l ))
      | (g, _) :: _ as functions ->
          let function_count = List.length functions in
          let* env_typ = Type.rec_env_type ~function_count ~free_variable_count in
          let env =
            if Code.Var.equal f g
            then
              let env = Code.Var.fresh () in
              let* () = set_closure_env f env in
              let* l = expression_list load free_variables in
              tee
                env
                (return
                   (W.StructNew
                      ( env_typ
                      , List.init ~len:function_count ~f:(fun _ ->
                            W.I31New (W.Const (I32 0l)))
                        @ l )))
            else
              let* env = get_closure_env g in
              let* () = set_closure_env f env in
              load env
          in
          let* typ = Type.rec_closure_type ~arity ~function_count ~free_variable_count in
          let res =
            let* env = (*ZZZ remove *) Memory.wasm_cast env_typ env in
            return
              (W.StructNew
                 ( typ
                 , (if arity = 1
                    then [ W.Const (I32 1l); RefFunc (V f) ]
                    else
                      [ Const (I32 (Int32.of_int arity))
                      ; RefFunc (V curry_fun)
                      ; RefFunc (V f)
                      ])
                   @ [ env ] ))
          in
          if is_last_fun functions f
          then
            seq
              (snd
                 (List.fold_left
                    ~f:(fun (i, prev) (g, _) ->
                      ( i + 1
                      , let* () = prev in
                        Memory.wasm_struct_set
                          env_typ
                          (Memory.wasm_cast env_typ env)
                          i
                          (if Code.Var.equal f g then tee f res else load g) ))
                    ~init:(0, return ())
                    functions))
              (load f)
          else res

  let bind_environment ~context ~closures f =
    if Hashtbl.mem context.constants f
    then
      (* The closures are all constants and the environment is empty. *)
      let* _ = add_var (Code.Var.fresh ()) in
      return ()
    else
      let info = Code.Var.Map.find f closures in
      let free_variables = get_free_variables ~context info in
      let free_variable_count = List.length free_variables in
      let arity = List.assoc f info.functions in
      let offset = if arity = 1 then 2 else 3 in
      match info.Wa_closure_conversion.functions with
      | [ _ ] ->
          let* typ = Type.env_type ~arity free_variable_count in
          let* _ = add_var f in
          (*ZZZ Store env with right type in local variable? *)
          snd
            (List.fold_left
               ~f:(fun (i, prev) x ->
                 ( i + 1
                 , let* () = prev in
                   define_var x Memory.(wasm_struct_get typ (wasm_cast typ (load f)) i) ))
               ~init:(offset, return ())
               free_variables)
      | functions ->
          let function_count = List.length functions in
          let* typ = Type.rec_closure_type ~arity ~function_count ~free_variable_count in
          let* _ = add_var f in
          let env = Code.Var.fresh_n "env" in
          let* () =
            store env Memory.(wasm_struct_get typ (wasm_cast typ (load f)) offset)
          in
          let* typ = Type.rec_env_type ~function_count ~free_variable_count in
          snd
            (List.fold_left
               ~f:(fun (i, prev) x ->
                 ( i + 1
                 , let* () = prev in
                   (*ZZZ Avoid cast? *)
                   define_var x Memory.(wasm_struct_get typ (wasm_cast typ (load env)) i)
                 ))
               ~init:(0, return ())
               (List.map ~f:fst functions @ free_variables))

  let curry_allocate ~stack_ctx:_ ~x:_ ~arity m ~f ~closure ~arg =
    let* ty = Type.curry_type arity m in
    let* cl_ty =
      if m = arity then Type.closure_type arity else Type.curry_type arity (m + 1)
    in
    let* closure = Memory.wasm_cast cl_ty (load closure) in
    let* arg = load arg in
    return (W.StructNew (ty, [ Const (I32 1l); RefFunc f; closure; arg ]))

  let curry_load ~arity m closure =
    let* ty = Type.curry_type arity m in
    (*ZZZ Remove casts*)
    return
      ( Memory.wasm_struct_get ty (Memory.wasm_cast ty (load closure)) 2
      , Memory.wasm_struct_get ty (Memory.wasm_cast ty (load closure)) 3 )
end

module Stack = struct
  type stack = Code.Var.t option list

  type info = unit

  let generate_spilling_information _ ~context:_ ~closures:_ ~pc:_ ~env:_ ~params:_ = ()

  let add_spilling _ ~location:_ ~stack:_ ~live_vars:_ ~spilled_vars:_ = (), []

  type ctx = unit

  let start_function ~context:_ _ = ()

  let start_block ~context:_ _ _ = ()

  let perform_reloads _ _ = return ()

  let perform_spilling _ _ = return ()

  let kill_variables _ = ()

  let assign _ _ = return ()

  let make_info () = ()

  let adjust_stack _ ~src:_ ~dst:_ = return ()

  let stack_adjustment_needed _ ~src:_ ~dst:_ = false
end

let entry_point ~register_primitive:_ = return ()
