%%%=============================================================================
%% Copyright 2016- AUTHORS
%% Copyright (c) 2026 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%%
%% @doc jesse test utility functions.
%%
%% The per-draft CT suites are data-driven off the official
%% JSON-Schema-Test-Suite: `load_tests/3' discovers every `*.json' file in a
%% tests directory, and `run_all/1' walks every case and assertion in one go,
%% collecting *all* failures before reporting (rather than aborting on the
%% first). Test files are discovered by globbing, so adding/removing a keyword
%% file upstream needs no suite change.
%%
%% A `skip_list' of `{FileKey, Pattern}' entries lets a suite exclude cases
%% jesse does not (yet) support; `Pattern' is either a case description binary
%% or the atom `_' to skip a whole file. Every skip is reported in the summary,
%% never silently dropped.
%% @end
%%%=============================================================================

-module(jesse_tests_util).

%% API
-export([ load_tests/3
        , run_all/1
        , start_remotes_server/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

%% JSON-Schema-Test-Suite attributes definitions
-define(DATA,        <<"data">>).
-define(DESCRIPTION, <<"description">>).
-define(OPTIONS,     <<"options">>).
-define(SCHEMA,      <<"schema">>).
-define(TESTS,       <<"tests">>).
-define(VALID,       <<"valid">>).

-ifdef(OTP_RELEASE). %% OTP 21+
-define(EXCEPTION(C, R, Stacktrace), C:R:Stacktrace ->).
-else.
-define( EXCEPTION(C, R, Stacktrace)
       , C:R -> Stacktrace = erlang:get_stacktrace(),
       ).
-endif.

%%% API

%% @doc Load every `*.json' test file under `RelativeTestsDir' (relative to the
%% suite's data_dir) and pair each with the dialect `DefaultSchema' to use for
%% schemas that don't declare their own `$schema'. Returns a list of
%% `{FileKey, {Cases, DefaultSchema}}'.
load_tests(RelativeTestsDir, DefaultSchema, Config) ->
  TestsDir = filename:join(?config(data_dir, Config), RelativeTestsDir),
  TestFiles = filelib:wildcard(TestsDir ++ "/*.json"),
  lists:map( fun(TestFile) ->
                 {ok, Bin} = file:read_file(TestFile),
                 Cases = jsx:decode(Bin, [{return_maps, false}]),
                 {testfile_to_key(TestFile), {Cases, DefaultSchema}}
             end
           , TestFiles
           ).

%% @doc Run every loaded case/assertion, honouring the `skip_list', collecting
%% all outcomes, printing a summary, and failing the CT case if any
%% non-skipped assertion failed or crashed.
%%
%% Expects `Config' to carry `{all_tests, [{FileKey, {Cases, Schema}}]}' and
%% `{skip_list, [{FileKey, Pattern}]}'.
run_all(Config) ->
  AllTests = ?config(all_tests, Config),
  SkipList = ?config(skip_list, Config),
  warn_stale_skips(AllTests, SkipList),
  Results = lists:flatmap( fun({Key, {Cases, Schema}}) ->
                              run_file(Key, Cases, Schema, SkipList)
                          end
                         , AllTests
                         ),
  report(Results),
  Bad = [R || R <- Results, is_bad(R)],
  case Bad of
    [] -> ok;
    _  -> ct:fail({unexpected_failures, length(Bad)})
  end.

%% @doc Warn about skip-list entries that no longer match any loaded case.
%% Case descriptions drift as the upstream suite evolves, so a stale skip
%% silently loses coverage; surfacing it keeps the skip-list honest across
%% test-suite bumps.
warn_stale_skips(AllTests, SkipList) ->
  Present = [ {list_to_binary(Key), get_path(?DESCRIPTION, Case)}
              || {Key, {Cases, _}} <- AllTests, Case <- Cases ],
  Files   = [list_to_binary(Key) || {Key, _} <- AllTests],
  Stale =
    [ Entry
      || {K, Pat} = Entry <- SkipList,
         case Pat of
           '_' -> not lists:member(K, Files);
           _   -> not lists:member({K, Pat}, Present)
         end
    ],
  case Stale of
    [] -> ok;
    _  -> ct:pal("WARNING stale skip_list entries (no matching case):~n  ~p",
                 [Stale])
  end.

%% @doc Start an httpd instance serving the `remotes' directory on port 1234,
%% as required by the `refRemote' tests. Idempotent-ish: safe to call once per
%% suite from init_per_suite.
start_remotes_server(Config) ->
  DocumentRoot = filename:join(?config(data_dir, Config), "remotes"),
  Port = 1234,
  ServerOpts = [ {port, Port}
               , {server_name, "localhost"}
               , {server_root, "."}
               , {document_root, DocumentRoot}
               ],
  {ok, _} = application:ensure_all_started(inets),
  case inets:start(httpd, ServerOpts) of
    {ok, _Pid} ->
      ok;
    %% Every suite serves the same remotes content but via its own symlink, so
    %% the config differs and a later start clashes on the port. That is fine
    %% *iff* the bound server is really our remotes server; verify it. Any
    %% other error is a genuine harness failure and must abort init_per_suite
    %% (not be mistaken for a conformance failure).
    {error, {already_started, _}} ->
      verify_remotes_server(Port, DocumentRoot);
    {error, eaddrinuse} ->
      verify_remotes_server(Port, DocumentRoot);
    {error, {listen, eaddrinuse}} ->
      verify_remotes_server(Port, DocumentRoot);
    {error, Reason} ->
      error({failed_to_start_remotes_server, Reason})
  end.

%% @doc Confirm that whatever already holds `Port' is a remotes server serving
%% the content we expect (a previous suite in this node), not a foreign process
%% or another document root: fetch a known fixture over HTTP and byte-compare it
%% to the file on disk. `Expected' is bound before the request, so the success
%% clause only matches when the served bytes are identical.
%% @private
verify_remotes_server(Port, DocumentRoot) ->
  {ok, Expected} = file:read_file(filename:join(DocumentRoot, "integer.json")),
  Url = "http://localhost:" ++ integer_to_list(Port) ++ "/integer.json",
  case httpc:request(get, {Url, []}, [], [{body_format, binary}]) of
    {ok, {{_, 200, _}, _, Expected}} ->
      ok;
    {ok, {{_, 200, _}, _, Other}} ->
      error({remotes_server_wrong_content, Port, Url, Other});
    Other ->
      error({remotes_server_unreachable, Port, Url, Other})
  end.

%%% Internal functions

run_file(Key, Cases, DefaultSchema, SkipList) ->
  KeyBin = list_to_binary(Key),
  lists:flatmap( fun(Case) ->
                     run_case(Key, KeyBin, Case, DefaultSchema, SkipList)
                 end
               , Cases
               ).

run_case(Key, KeyBin, Case, DefaultSchema, SkipList) ->
  CaseDesc = get_path(?DESCRIPTION, Case),
  case is_skipped(KeyBin, CaseDesc, SkipList) of
    true ->
      [{Key, CaseDesc, <<"*">>, skip}];
    false ->
      Schema      = get_path(?SCHEMA, Case),
      Opts0       = get_path(?OPTIONS, Case),
      SchemaTests = get_path(?TESTS, Case),
      Opts = [ {default_schema_ver, DefaultSchema}
             , {schema_loader_fun, fun load_schema/1}
             ] ++ make_options(Opts0),
      [ run_assertion(Key, CaseDesc, Schema, Opts, Test)
        || Test <- SchemaTests ]
  end.

run_assertion(Key, CaseDesc, Schema, Opts, Test) ->
  TestDesc = get_path(?DESCRIPTION, Test),
  Instance = get_path(?DATA, Test),
  Expected = get_path(?VALID, Test),
  Outcome =
    try jesse:validate_with_schema(Schema, Instance, Opts) of
      Result -> check_result(Expected, Instance, Result)
    catch ?EXCEPTION(C, R, Stacktrace)
      {crash, {C, R, hd_or_undefined(Stacktrace)}}
    end,
  {Key, CaseDesc, TestDesc, Outcome}.

%% @doc A JSON-Schema-Test-Suite `valid' field is a boolean; jesse's own
%% `extra' tests may instead list the expected error atoms.
check_result(true, Instance, Result) ->
  case Result of
    {ok, Instance} -> pass;
    _              -> {fail, {expected_valid, Result}}
  end;
check_result(false, _Instance, Result) ->
  case Result of
    {error, _} -> pass;
    _          -> {fail, {expected_invalid, Result}}
  end;
check_result(ExpectedErrors, _Instance, {error, Errors})
  when is_list(ExpectedErrors) ->
  GotErrors = [atom_to_binary(E, utf8) || {data_invalid, _, E, _, _} <- Errors],
  case ExpectedErrors == GotErrors of
    true  -> pass;
    false -> {fail, {unexpected_error, GotErrors}}
  end;
check_result(ExpectedErrors, _Instance, Result) when is_list(ExpectedErrors) ->
  {fail, {expected_errors, ExpectedErrors, Result}}.

is_bad({_Key, _Case, _Test, pass}) -> false;
is_bad({_Key, _Case, _Test, skip}) -> false;
is_bad(_) -> true.

is_skipped(KeyBin, CaseDesc, SkipList) ->
  lists:member({KeyBin, CaseDesc}, SkipList)
    orelse lists:member({KeyBin, '_'}, SkipList).

report(Results) ->
  Total   = length(Results),
  Passed  = length([R || R = {_, _, _, pass} <- Results]),
  Skipped = length([R || R = {_, _, _, skip} <- Results]),
  Bad     = [R || R <- Results, is_bad(R)],
  ct:pal( "JSON-Schema-Test-Suite results:~n"
          "  total    : ~p~n"
          "  passed   : ~p~n"
          "  skipped  : ~p~n"
          "  failed   : ~p~n"
        , [Total, Passed, Skipped, length(Bad)]
        ),
  lists:foreach( fun({Key, CaseDesc, TestDesc, Outcome}) ->
                     ct:pal( "FAILED [~s] ~ts / ~ts~n  ~p"
                           , [Key, CaseDesc, TestDesc, Outcome]
                           )
                 end
               , Bad
               ).

make_options([]) ->
  [];
make_options(Options) ->
  lists:map( fun ({Key0, Value0}) ->
                 Key = maybe_atom(Key0),
                 Value = maybe_atom(Value0),
                 {Key, Value}
             end
           , Options
           ).

maybe_atom(Bin) when is_binary(Bin) ->
  list_to_existing_atom(binary_to_list(Bin));
maybe_atom(Other) ->
  Other.

hd_or_undefined([H | _]) -> H;
hd_or_undefined(_) -> undefined.

testfile_to_key(TestFile) ->
  filename:rootname(filename:basename(TestFile)).

get_path(Key, Schema) ->
  jesse_json_path:path(Key, Schema).

load_schema(URI) ->
  HttpOptions = [{ssl, [{verify, verify_none}]}],
  {ok, Response} = httpc:request( get
                                , {URI, []}
                                , HttpOptions
                                , [{body_format, binary}]),
  {{_Line, 200, _}, _Headers, Body} = Response,
  jsx:decode(Body, [{return_maps, false}]).
