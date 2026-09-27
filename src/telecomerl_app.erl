-module(telecomerl_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    telecomerl_server:start_link().

stop(_State) ->
    ok.