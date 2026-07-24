%%%=============================================================================
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
%% @doc Draft 2020-12 conformance against the official JSON-Schema-Test-Suite.
%% Test files are auto-discovered; unsupported cases are in skip_list/0.
%% @end
%%%=============================================================================

-module(jesse_tests_draft2020_12_SUITE).

-compile([ export_all
         , nowarn_export_all
         ]).

-include_lib("common_test/include/ct.hrl").

-define(META, <<"https://json-schema.org/draft/2020-12/schema">>).

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

%% @doc Cases jesse does not (yet) support for draft 2020-12. `{File, '_'}'
%% skips a whole file; `{File, Description}' skips one case. Unsupported
%% keywords hard-error rather than false-accept, so skipping is safe.
skip_list() ->
  [ %% --- dynamic / recursive referencing (dynamic scope stack) ---
    %% "$dynamicRef"/"$dynamicAnchor" hard-error rather than false-accept.
    {<<"dynamicRef">>, '_'}
  , {<<"ref">>, <<"Recursive references between schemas">>}
  , {<<"unevaluatedItems">>, <<"unevaluatedItems with $dynamicRef">>}
  , {<<"unevaluatedProperties">>,
     <<"unevaluatedProperties with $dynamicRef">>}
    %% --- in-document "$id" / base-URI resolution (nearest-parent scoping,
    %% location-independent identifiers, refs resolved against $id bases) ---
  , {<<"anchor">>, <<"Location-independent identifier with absolute URI">>}
  , {<<"anchor">>, <<"Location-independent identifier with base URI change"
                     " in subschema">>}
  , {<<"anchor">>, <<"same $anchor with different base uri">>}
  , {<<"ref">>, <<"$id must be resolved against nearest parent, not just"
                  " immediate parent">>}
  , {<<"ref">>, <<"order of evaluation: $id and $ref">>}
  , {<<"ref">>, <<"order of evaluation: $id and $ref on nested schema">>}
  , {<<"ref">>, <<"refs with relative uris and defs">>}
  , {<<"ref">>, <<"relative refs with absolute uris and defs">>}
  , {<<"ref">>, <<"ref with absolute-path-reference">>}
  , {<<"ref">>, <<"ref to if">>}
  , {<<"ref">>, <<"ref to then">>}
  , {<<"ref">>, <<"ref to else">>}
  , {<<"refRemote">>, <<"base URI change - change folder">>}
  , {<<"refRemote">>, <<"base URI change - change folder in subschema">>}
  , {<<"refRemote">>, <<"remote HTTP ref with nested absolute ref">>}
    %% --- "urn:" scheme base URIs ---
  , {<<"ref">>, <<"URN ref with nested pointer ref">>}
    %% --- empty-string reference tokens ("#/$defs//...") ---
  , {<<"ref">>, <<"empty tokens in $ref json-pointer">>}
    %% --- remote metaschema fetch ("$ref" to the 2020-12 metaschema) ---
  , {<<"defs">>, <<"validate definition against metaschema">>}
    %% --- custom metaschema "$vocabulary" processing ---
  , {<<"vocabulary">>, '_'}
    %% --- ECMA-262 "\p{...}" unicode property escapes: Erlang's re/PCRE only
    %% accepts short property names (e.g. \p{L}), so \p{Letter} fails to
    %% compile. Needs a property-name translation layer. ---
  , {<<"pattern">>, <<"pattern with Unicode property escape"
                      " requires unicode mode">>}
  , {<<"patternProperties">>, <<"patternProperties with Unicode"
                                " property escape">>}
  ].
