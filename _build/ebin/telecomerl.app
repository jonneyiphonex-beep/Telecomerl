{application, telecomerl,
 [{description, "Telecom SIM, APN and connectivity diagnostics"},
  {vsn, "1.0.0"},
  {registered, [telecomerl_server]},
  {mod, {telecomerl_app, []}},
  {applications, [kernel, stdlib, crypto, inets, ssl]},
  {env, []},
  {modules, [telecomerl, telecomerl_app, telecomerl_server]}]}.