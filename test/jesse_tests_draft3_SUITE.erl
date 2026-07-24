%%%=============================================================================
%% Copyright 2012- Klarna AB
%% Copyright 2015- AUTHORS
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
%% @doc Draft 03 conformance against the official JSON-Schema-Test-Suite.
%% Test files are auto-discovered; unsupported cases are in skip_list/0.
%% @end
%%%=============================================================================

-module(jesse_tests_draft3_SUITE).

-compile([ export_all
         , nowarn_export_all
         ]).

-include_lib("common_test/include/ct.hrl").

-define(META, <<"http://json-schema.org/draft-03/schema#">>).

all() ->
  [conformance].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(jesse),
  jesse_tests_util:start_remotes_server(Config),
  AllTests = jesse_tests_util:load_tests("standard", ?META, Config)
             ++ jesse_tests_util:load_tests("extra", ?META, Config),
  [{all_tests, AllTests}, {skip_list, skip_list()} | Config].

end_per_suite(_Config) ->
  ok.

conformance(Config) ->
  jesse_tests_util:run_all(Config).

%% @doc Cases jesse does not (yet) support for draft 03. `{File, '_'}' skips a
%% whole file; `{File, Description}' skips one case.
skip_list() ->
  [ %% in-document "id" base-URI resolution (a sibling id changing the base
    %% URI) is not implemented; see the $id/$ref scoping follow-up.
    {<<"ref">>, <<"$ref prevents a sibling id from changing the base uri">>}
  ].
