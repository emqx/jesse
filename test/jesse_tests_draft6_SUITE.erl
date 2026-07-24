%%%=============================================================================
%% Copyright 2022- AUTHORS
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
%% @doc Draft 06 conformance against the official JSON-Schema-Test-Suite.
%% Test files are auto-discovered; unsupported cases are in skip_list/0.
%% @end
%%%=============================================================================

-module(jesse_tests_draft6_SUITE).

-compile([ export_all
         , nowarn_export_all
         ]).

-include_lib("common_test/include/ct.hrl").

-define(META, <<"http://json-schema.org/draft-06/schema#">>).

all() ->
  [conformance].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(jesse),
  Httpd = jesse_tests_util:start_remotes_server(Config),
  AllTests = jesse_tests_util:load_tests("standard", ?META, Config)
             ++ jesse_tests_util:load_tests("extra", ?META, Config),
  [{httpd, Httpd}, {all_tests, AllTests}, {skip_list, skip_list()} | Config].

end_per_suite(Config) ->
  jesse_tests_util:stop_remotes_server(?config(httpd, Config)),
  ok.

conformance(Config) ->
  jesse_tests_util:run_all(Config).

%% @doc Cases jesse does not (yet) support for draft 06. `{File, '_'}' skips a
%% whole file; `{File, Description}' skips one case.
skip_list() ->
  [ %% in-document "$id"/base-URI resolution: location-independent identifiers,
    %% a sibling $id changing the base, relative/absolute-path refs resolved
    %% against $id bases, anchors reached via a non-relative URI.
    {<<"ref">>, <<"$ref prevents a sibling $id from changing the base uri">>}
  , {<<"ref">>, <<"Location-independent identifier">>}
  , {<<"ref">>, <<"Location-independent identifier with base URI change"
                  " in subschema">>}
  , {<<"ref">>, <<"Reference an anchor with a non-relative URI">>}
  , {<<"ref">>, <<"refs with relative uris and defs">>}
  , {<<"ref">>, <<"relative refs with absolute uris and defs">>}
  , {<<"ref">>, <<"ref with absolute-path-reference">>}
  , {<<"refRemote">>, <<"Location-independent identifier in remote ref">>}
  , {<<"refRemote">>, <<"$ref to $ref finds location-independent $id">>}
    %% "urn:" scheme base URIs are not supported.
  , {<<"ref">>, <<"URN base URI with URN and anchor ref">>}
    %% recursive references between separate schema documents.
  , {<<"ref">>, <<"Recursive references between schemas">>}
    %% empty-string reference tokens ("#/definitions//...").
  , {<<"ref">>, <<"empty tokens in $ref json-pointer">>}
  ].
