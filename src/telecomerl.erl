-module(telecomerl).
-export([start/0, stop/0]).

start() ->
    application:ensure_all_started(crypto),
    application:ensure_all_started(inets),
    application:ensure_all_started(ssl),
    application:load(telecomerl),
    application:ensure_all_started(telecomerl).

stop() ->
    application:stop(telecomerl).