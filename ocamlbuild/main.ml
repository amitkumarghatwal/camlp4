(***********************************************************************)
(*                             ocamlbuild                              *)
(*                                                                     *)
(*  Nicolas Pouillard, Berke Durak, projet Gallium, INRIA Rocquencourt *)
(*                                                                     *)
(*  Copyright 2007 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)
(* Original author: Berke Durak *)
open My_std
open Log
open Pathname.Operators
open Command
open Tools
open Ocaml_specific
open Format
;;

exception Exit_build_error of string
exception Exit_silently

let clean () =
  Shell.rm_rf !Options.build_dir;
  begin
    match !Options.internal_log_file with
    | None -> ()
    | Some fn -> Shell.rm_f fn
  end;
  let entry =
    Slurp.map (fun _ _ _ -> true)
      (Slurp.slurp Filename.current_dir_name)
  in
  Slurp.force (Pathname.clean_up_links entry);
  raise Exit_silently
;;

let proceed () =
  Hooks.call_hook Hooks.Before_options;
  Options.init ();
  if !Options.must_clean then clean ();
  Hooks.call_hook Hooks.After_options;
  Tools.default_tags := Tags.of_list !Options.tags;
  Plugin.execute_plugin_if_needed ();

  if !Options.targets = [] then raise Exit_silently;

  let target_dirs = List.union [] (List.map Pathname.dirname !Options.targets) in

  let newpwd = Sys.getcwd () in
  Sys.chdir Pathname.pwd;
  let entry_include_dirs = ref [] in
  let entry =
    Slurp.filter
      begin fun path name _ ->
        let dir =
          if path = Filename.current_dir_name then
            None
          else
            Some path
        in
        let path_name = path/name in
        if name = "_tags" then
          ignore (Configuration.parse_file ?dir path_name);

        (String.length name > 0 && name.[0] <> '_' && not (List.mem name !Options.exclude_dirs))
        && begin
          if path_name <> Filename.current_dir_name && Pathname.is_directory path_name then
            let tags = tags_of_pathname path_name in
            if Tags.mem "include" tags
            || List.mem path_name !Options.include_dirs then
              (entry_include_dirs := path_name :: !entry_include_dirs; true)
            else
              Tags.mem "traverse" tags
              || List.exists (Pathname.is_prefix path_name) !Options.include_dirs
              || List.exists (Pathname.is_prefix path_name) target_dirs
          else true
        end
      end
      (Slurp.slurp Filename.current_dir_name)
  in
  let hygiene_entry =
    Slurp.map begin fun path name () ->
      let tags = tags_of_pathname (path/name) in
      not (Tags.mem "not_hygienic" tags) && not (Tags.mem "precious" tags)
    end entry in
  Hooks.call_hook Hooks.Before_hygiene;
  let entry =
    if !Options.hygiene then
      Fda.inspect hygiene_entry
    else
      (Slurp.force hygiene_entry; hygiene_entry)
  in
  Hooks.call_hook Hooks.After_hygiene;
  Options.include_dirs := Pathname.current_dir_name :: List.rev !entry_include_dirs;
  dprintf 3 "include directories are:@ %a" print_string_list !Options.include_dirs;
  Options.entry := Some entry;

  Hooks.call_hook Hooks.Before_rules;
  Ocaml_specific.init ();
  Hooks.call_hook Hooks.After_rules;

  Sys.chdir newpwd;
  (*let () = dprintf 0 "source_dir_path_set:@ %a" StringSet.print source_dir_path_set*)

  dprintf 8 "Rules are:@ %a" (List.print Rule.print) (Rule.get_rules ());
  Resource.Cache.init ();

  Configuration.parse_string
    "<**/*.ml> or <**/*.mli> or <**/*.mlpack> or <**/*.ml.depends>: ocaml
     <**/*.byte>: ocaml, byte, program
     <**/*.odoc>: ocaml, doc
     <**/*.native>: ocaml, native, program
     <**/*.cma>: ocaml, byte, library
     <**/*.cmxa>: ocaml, native, library
     <**/*.cmo>: ocaml, byte
     <**/*.cmi>: ocaml, byte, native
     <**/*.cmx>: ocaml, native
    ";

  Sys.catch_break true;

  let targets =
    List.map begin fun starget ->
      let target = path_and_context_of_string starget in
      let ext = Pathname.get_extension starget in
      (target, starget, ext)
    end !Options.targets in

  try
    let targets =
      List.map begin fun (target, starget, ext) ->
        Shell.mkdir_p (Pathname.dirname starget);
        let target = Solver.solve_target starget target in
        (target, ext)
      end targets in

    Log.finish ();

    Shell.chdir Pathname.pwd;

    let call spec = sys_command (Command.string_of_command_spec spec) in

    let cmds =
      List.fold_right begin fun (target, ext) acc ->
        let cmd = !Options.build_dir/target in
        if ext = "byte" || ext = "native" then begin
          if !Options.make_links then ignore (call (S [A"ln"; A"-sf"; P cmd; A Pathname.current_dir_name]));
          cmd :: acc
        end else begin
          if !Options.program_to_execute then
            eprintf "Warning: Won't execute %s whose extension is neither .byte nor .native" cmd;
          acc
        end
      end targets [] in

    if !Options.program_to_execute then
      begin
        match List.rev cmds with
        | [] -> raise (Exit_usage "Using -- requires one target");
        | cmd :: rest ->
          if rest <> [] then dprintf 0 "Warning: Using -- only run the last target";
          let cmd_spec = S [P cmd; atomize !Options.program_args] in
          dprintf 3 "Running the user command:@ %a" Pathname.print cmd;
          raise (Exit_with_code (call cmd_spec)) (* Exit with the exit code of the called command *)
      end
    else
      ()
  with
  | Ocaml_dependencies.Circular_dependencies(seen, p) ->
      raise
        (Exit_build_error
          (sbprintf "@[<2>Circular dependencies: %S already seen in@ %a@]@." p pp_l seen))
;;

module Exit_codes =
  struct
    let rc_ok                  = 0
    let rc_usage               = 1
    let rc_failure             = 2
    let rc_invalid_argument    = 3
    let rc_system_error        = 4
    let rc_hygiene             = 1
    let rc_circularity         = 5
    let rc_solver_failed       = 6
    let rc_ocamldep_error      = 7
    let rc_lexing_error        = 8
    let rc_build_error         = 9
    let rc_executor_reserved_1 = 10 (* Redefined in Executor *)
    let rc_executor_reserved_2 = 11
    let rc_executor_reserved_3 = 12
    let rc_executor_reserved_4 = 13
  end

open Exit_codes;;

let main () =
  let exit rc =
    Log.finish ~how:(if rc <> 0 then `Error else `Success) ();
    Pervasives.exit rc
  in
  try
    proceed ()
  with
  | Exit_OK -> exit rc_ok
  | Fda.Exit_hygiene_failed ->
      Log.eprintf "Exiting due to hygiene violations (try -sterilize).";
      exit rc_hygiene
  | Exit_usage u ->
      Log.eprintf "Usage:@ %s." u;
      exit rc_usage
  | Exit_system_error msg ->
      Log.eprintf "System error:@ %s." msg;
      exit rc_system_error
  | Exit_with_code rc ->
      exit rc
  | Exit_silently ->
      Log.finish ~how:`Quiet ();
      Pervasives.exit rc_ok
  | Exit_silently_with_code rc ->
      Log.finish ~how:`Quiet ();
      Pervasives.exit rc
  | Solver.Failed backtrace ->
      Log.raw_dprintf (-1) "@[<v0>@[<2>Solver failed:@ %a@]@\n@[<v2>Backtrace:%a@]@]@."
        Report.print_backtrace_analyze backtrace Report.print_backtrace backtrace;
      exit rc_solver_failed
  | Failure s ->
      Log.eprintf "Failure:@ %s." s;
      exit rc_failure
  | Solver.Circular(r, rs) ->
      Log.eprintf "Circular build detected@ (%a already seen in %a)"
      Resource.print r (List.print Resource.print) rs;
      exit rc_circularity
  | Invalid_argument s ->
      Log.eprintf
        "INTERNAL ERROR: Invalid argument %s\n\
         This is likely to be a bug, please report this to the ocamlbuild\n\
         developers." s;
      exit rc_invalid_argument
  | Ocamldep.Error msg ->
      Log.eprintf "Ocamldep error: %s" msg;
      exit rc_ocamldep_error
  | Lexers.Error msg ->
      Log.eprintf "Lexical analysis error: %s" msg;
      exit rc_lexing_error
  | Arg.Bad msg ->
      Log.eprintf "%s" msg;
      exit rc_usage
  | Exit_build_error msg ->
      Log.eprintf "%s" msg;
      exit rc_build_error
  | Arg.Help msg ->
      Log.eprintf "%s" msg;
      exit rc_ok
  | e ->
      try
        Log.eprintf "%a" My_unix.report_error e;
        exit 100 
      with
      | e ->
        Log.eprintf "Exception@ %s." (Printexc.to_string e);
        exit 100
;;