% roaming services and vas services
-module(telecomerl_server).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(DEFAULT_PORT, 8080).
-define(DEFAULT_INTERVAL, 5000).
-define(MAX_HEADER_BYTES, 32768).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Port = env_integer("PORT", ?DEFAULT_PORT, 1, 65535),
    Interval = env_integer("CHECK_INTERVAL_MS", ?DEFAULT_INTERVAL, 5000, 300000),
    ProbeUrls = probe_urls(),
    {ok, ListenSocket} = gen_tcp:listen(Port, [binary, {packet, raw},
        {active, false}, {reuseaddr, true}, {backlog, 128}]),
    spawn_link(fun() -> accept_loop(ListenSocket) end),
    self() ! refresh,
    {ok, #{port => Port, interval => Interval, probe_urls => ProbeUrls,
           snapshot => empty_snapshot(), checked_at => 0}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(refresh, State) ->
    self() ! refresh,
    {noreply, State};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(refresh, State) ->
    erlang:send_after(maps:get(interval, State), self(), refresh),
    case maps:get(refreshing, State, false) of
        true -> {noreply, State};
        false ->
            Parent = self(),
            ProbeUrls = maps:get(probe_urls, State),
            spawn(fun() ->
                Snapshot = try collect_status(ProbeUrls)
                           catch _:_ -> empty_snapshot() end,
                Parent ! {refresh_complete, Snapshot}
            end),
            {noreply, State#{refreshing => true}}
    end;
handle_info({refresh_complete, Snapshot}, State) ->
    {noreply, State#{snapshot := Snapshot, refreshing := false,
                     checked_at := erlang:system_time(second)}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

empty_snapshot() ->
    #{internet => [], modem => #{available => false, registration => "unknown",
       operator => "", radio => "unknown", apn => "", connection => "",
       sim => "unknown"}, network => #{available => false, state => "unknown",
       connection => "", type => "", ip => "", gateway => ""}}.

accept_loop(ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} ->
            spawn(fun() -> handle_client(Socket) end),
            accept_loop(ListenSocket);
        {error, closed} -> ok;
        {error, _Reason} ->
            timer:sleep(100),
            accept_loop(ListenSocket)
    end.

handle_client(Socket) ->
    try
        case recv_headers(Socket, <<>>) of
            {ok, Header} ->
                [RequestLine | _] = binary:split(Header, <<"\r\n">>, [global]),
                Parts = binary:split(RequestLine, <<" ">>, [global]),
                respond(Socket, Parts);
            {error, _Reason} -> send_response(Socket, 400, "text/plain", "Bad request")
        end
    catch
        _:_ -> send_response(Socket, 400, "text/plain", "Bad request")
    after
        gen_tcp:close(Socket)
    end.

recv_headers(_Socket, Buffer) when byte_size(Buffer) > ?MAX_HEADER_BYTES ->
    {error, header_too_large};
recv_headers(Socket, Buffer) ->
    case binary:match(Buffer, <<"\r\n\r\n">>) of
        {_, _} -> {ok, Buffer};
        nomatch ->
            case gen_tcp:recv(Socket, 0, 5000) of
                {ok, Data} -> recv_headers(Socket, <<Buffer/binary, Data/binary>>);
                Error -> Error
            end
    end.

respond(Socket, [Method, Target, _Version]) when Method =:= <<"GET">> ->
    [Path | QueryParts] = binary:split(Target, <<"?">>),
    Query = case QueryParts of [Value] -> Value; [] -> <<>> end,
    case Path of
        <<"/api/status">> -> serve_status(Socket);
        <<"/api/refresh">> -> gen_server:cast(?MODULE, refresh), serve_status(Socket);
        _ -> serve_static(Socket, Path, Query)
    end;
respond(Socket, _Parts) ->
    send_response(Socket, 405, "text/plain", "Method not allowed").

serve_status(Socket) ->
    State = sys:get_state(?MODULE),
    Snapshot = maps:get(snapshot, State),
    Body = json_encode(#{ok => true, checked_at => maps:get(checked_at, State),
        interval_ms => maps:get(interval, State), port => maps:get(port, State),
        internet => maps:get(internet, Snapshot), modem => maps:get(modem, Snapshot),
        network => maps:get(network, Snapshot)}),
    send_response(Socket, 200, "application/json; charset=utf-8", Body,
                  [{"Cache-Control", "no-store"}]).

serve_static(Socket, Path, _Query) ->
    File = case Path of
        <<"/">> -> "index.html";
        <<"/index.html">> -> "index.html";
        <<"/app.css">> -> "app.css";
        <<"/app.js">> -> "app.js";
        _ -> undefined
    end,
    case File of
        undefined -> send_response(Socket, 404, "text/plain", "Not found");
        _ ->
            case file:read_file(filename:join(static_dir(), File)) of
                {ok, Body} -> send_response(Socket, 200, mime_type(File), Body,
                                            [{"Cache-Control", "no-cache"}]);
                {error, _} -> send_response(Socket, 500, "text/plain", "Static files unavailable")
            end
    end.

static_dir() ->
    case os:getenv("TELECOM_STATIC_DIR") of
        false -> "static";
        Dir -> Dir
    end.

mime_type("index.html") -> "text/html; charset=utf-8";
mime_type("app.css") -> "text/css; charset=utf-8";
mime_type("app.js") -> "application/javascript; charset=utf-8".

send_response(Socket, Status, ContentType, Body) ->
    send_response(Socket, Status, ContentType, Body, []).

send_response(Socket, Status, ContentType, Body, ExtraHeaders) ->
    Reason = case Status of 200 -> "OK"; 400 -> "Bad Request";
        404 -> "Not Found"; 405 -> "Method Not Allowed";
        _ -> "Internal Server Error" end,
    Headers = [[Name, ": ", Value, "\r\n"] || {Name, Value} <- ExtraHeaders],
    Response = ["HTTP/1.1 ", integer_to_list(Status), " ", Reason, "\r\n",
        "Content-Type: ", ContentType, "\r\n",
        "Content-Length: ", integer_to_list(iolist_size(Body)), "\r\n",
        "Connection: close\r\n", Headers, "X-Content-Type-Options: nosniff\r\n",
        "Referrer-Policy: no-referrer\r\n\r\n", Body],
    gen_tcp:send(Socket, Response).

collect_status(ProbeUrls) ->
    #{internet => [probe(Url) || Url <- ProbeUrls],
      modem => modem_status(), network => network_status()}.

probe(Url) ->
    Started = erlang:monotonic_time(millisecond),
    Result = try httpc:request(get, {Url, []},
        [{timeout, 5000}, {connect_timeout, 3000}], [{body_format, binary}])
    catch _:_ -> {error, request_failed} end,
    Elapsed = erlang:monotonic_time(millisecond) - Started,
    case Result of
        {ok, {{_Version, Code, _Phrase}, _Headers, _Body}} ->
            #{url => Url, online => Code >= 200 andalso Code < 400,
              status => Code, latency_ms => Elapsed, error => ""};
        {error, Reason} ->
            #{url => Url, online => false, status => 0, latency_ms => Elapsed,
              error => error_name(Reason)}
    end.

modem_status() ->
    case command_output("mmcli", ["-L"]) of
        {ok, ListOutput} ->
            case re:run(ListOutput, "/Modem/(\\d+)", [{capture, [1], list}]) of
                {match, [Index]} -> modem_details(Index);
                _ -> unavailable_modem()
            end;
        _ -> unavailable_modem()
    end.

unavailable_modem() ->
    #{available => false, registration => "unavailable", operator => "",
    radio => "unknown", apn => "", connection => "", sim => "unknown",
    roaming => "unknown"}.

modem_details(Index) ->
    case command_output("mmcli", ["-m", Index]) of
        {ok, Output} ->
                        Registration = match_value(Output, "registration: ([^\\r\\n]+)", "unknown"),
            #{available => true,
                            registration => Registration,
                            roaming => roaming_status(Registration),
              operator => match_value(Output, "operator name: ([^\\r\\n]+)", ""),
              radio => normalize_radio(match_value(Output, "access tech: ([^\\r\\n]+)", "unknown")),
              apn => active_apn(), connection => active_connection(),
              sim => sim_state(Output)};
        _ -> unavailable_modem()
    end.

sim_state(Output) ->
    case re:run(Output, "primary sim path: ([^\\r\\n]+)", [{capture, [1], list}]) of
        {match, [_]} -> "detected";
        _ -> "not detected"
    end.

roaming_status(Value) ->
    case string:lowercase(string:trim(Value)) of
        "roaming" -> "roaming";
        "home" -> "home";
        _ -> "unknown"
    end.

normalize_radio(Value) ->
    Lower = string:lowercase(string:trim(Value)),
    case has_radio(Lower, ["5g", "nr"]) of
        true -> "5G";
        false ->
            case has_radio(Lower, ["lte", "4g"]) of
                true -> "4G";
                false ->
                    case has_radio(Lower, ["umts", "hspa", "wcdma", "3g"]) of
                        true -> "3G";
                        false ->
                            case has_radio(Lower, ["gsm", "edge", "gprs", "2g"]) of
                                true -> "2G";
                                false -> string:uppercase(Lower)
                            end
                    end
            end
    end.

has_radio(_Value, []) -> false;
has_radio(Value, [Radio | Rest]) ->
    string:str(Value, Radio) > 0 orelse has_radio(Value, Rest).

network_status() ->
    case command_output("nmcli", ["-t", "-f", "GENERAL.CONNECTION,GENERAL.TYPE,GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY", "device", "show"]) of
        {ok, Output} ->
            Connection = first_field(Output, "GENERAL.CONNECTION:"),
            Type = first_field(Output, "GENERAL.TYPE:"),
            State = first_field(Output, "GENERAL.STATE:"),
            Ip = first_field(Output, "IP4.ADDRESS[1]:"),
            Gateway = first_field(Output, "IP4.GATEWAY:"),
            #{available => true, state => empty_unknown(State), connection => Connection,
              type => Type, ip => Ip, gateway => Gateway};
        _ -> #{available => false, state => "unavailable", connection => "",
               type => "", ip => "", gateway => ""}
    end.

active_connection() ->
    case command_output("nmcli", ["-g", "GENERAL.CONNECTION", "device", "show"]) of
        {ok, Output} -> first_nonempty(string:split(Output, "\n", all));
        _ -> ""
    end.

active_apn() ->
    case active_connection() of
        "" -> "";
        Connection ->
            case command_output("nmcli", ["-g", "gsm.apn", "connection", "show", Connection]) of
                {ok, Output} -> string:trim(Output);
                _ -> ""
            end
    end.

first_field(Output, Prefix) ->
    case [string:trim(Value) || Line <- string:split(Output, "\n", all),
         lists:prefix(Prefix, Line), Value <- [lists:nthtail(length(Prefix), Line)],
         Value =/= ""] of
        [Value | _] -> Value;
        [] -> ""
    end.

first_nonempty([Value | Rest]) ->
    Trimmed = string:trim(Value),
    case Trimmed of "" -> first_nonempty(Rest); _ -> Trimmed end;
first_nonempty([]) -> "".

empty_unknown("") -> "unknown";
empty_unknown(Value) -> Value.

match_value(Output, Pattern, Default) ->
    case re:run(Output, Pattern, [{capture, [1], list}]) of
        {match, [Value]} -> string:trim(Value);
        _ -> Default
    end.

command_output(Name, Args) ->
    case os:find_executable(Name) of
        false -> {error, unavailable};
        Executable ->
            try open_port({spawn_executable, Executable},
                [binary, use_stdio, stderr_to_stdout, exit_status, {args, Args}]) of
                Port -> collect_port(Port, <<>>)
            catch _:_ -> {error, unavailable} end
    end.

collect_port(Port, Acc) ->
    receive
        {Port, {data, Data}} -> collect_port(Port, <<Acc/binary, Data/binary>>);
        {Port, {exit_status, 0}} -> {ok, binary_to_list(Acc)};
        {Port, {exit_status, _}} -> {error, command_failed}
    after 2500 ->
        catch port_close(Port),
        {error, timeout}
    end.

probe_urls() ->
    case os:getenv("TELECOM_PROBE_URLS") of
        false -> ["https://connectivitycheck.gstatic.com/generate_204"];
        Value ->
            Urls = [string:trim(Url) || Url <- string:split(Value, ";", all),
                    valid_probe_url(string:trim(Url))],
            case Urls of [] -> ["https://connectivitycheck.gstatic.com/generate_204"]; _ -> Urls end
    end.

valid_probe_url(Url) ->
    lists:prefix("https://", Url) orelse lists:prefix("http://", Url).

env_integer(Name, Default, Min, Max) ->
    case os:getenv(Name) of
        false -> Default;
        Value ->
            try list_to_integer(Value) of
                Number when Number >= Min, Number =< Max -> Number;
                _ -> Default
            catch _:_ -> Default end
    end.

error_name({failed_connect, _}) -> "connection failed";
error_name(timeout) -> "timed out";
error_name(_) -> "request failed".

json_encode(Value) -> iolist_to_binary(json_value(Value)).

json_value(Value) when is_map(Value) ->
    Pairs = maps:to_list(Value),
    ["{", join([[json_string(key_string(Key)), ":", json_value(Item)]
                 || {Key, Item} <- Pairs], ","), "}"];
json_value(Value) when is_list(Value) ->
    case is_string(Value) of
        true -> json_string(Value);
        false -> ["[", join([json_value(Item) || Item <- Value], ","), "]"]
    end;
json_value(Value) when is_binary(Value) -> json_string(unicode:characters_to_list(Value));
json_value(true) -> "true";
json_value(false) -> "false";
json_value(null) -> "null";
json_value(Value) when is_integer(Value) -> integer_to_list(Value);
json_value(Value) when is_float(Value) -> float_to_list(Value, [short]);
json_value(Value) when is_atom(Value) -> json_string(atom_to_list(Value)).

key_string(Key) when is_atom(Key) -> atom_to_list(Key);
key_string(Key) -> Key.

is_string([]) -> true;
is_string(Value) -> lists:all(fun(Char) -> is_integer(Char) andalso Char >= 0 end, Value).

json_string(Value) -> ["\"", [json_char(Char) || Char <- Value], "\""].

json_char($") -> "\\\"";
json_char($\\) -> "\\\\";
json_char($\b) -> "\\b";
json_char($\f) -> "\\f";
json_char($\n) -> "\\n";
json_char($\r) -> "\\r";
json_char($\t) -> "\\t";
json_char(Char) when Char < 32 -> io_lib:format("\\u~4.16.0B", [Char]);
json_char(Char) -> unicode:characters_to_binary([Char]).

join([], _Separator) -> [];
join([Item], _Separator) -> Item;
join([Item | Rest], Separator) -> [Item, Separator, join(Rest, Separator)].