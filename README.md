# Telecomerl

Telecomerl includes an Erlang HTTP server for the network diagnostics dashboard.

## Run the web server

With Erlang/OTP and `make` installed, start the server directly:

```sh
make run
```

Or use Docker when Erlang is not installed on the host:

```sh
make webserver
```

Open [http://localhost:8080](http://localhost:8080). Set `PORT` to use a different port, for example `PORT=8081 make webserver`. Stop the foreground server with Ctrl+C.

The server serves the dashboard at `/` and exposes `GET /api/status` and `GET /api/refresh`. `CHECK_INTERVAL_MS` controls automatic checks (5,000 to 300,000 ms); `TELECOM_PROBE_URLS` accepts semicolon-separated HTTP or HTTPS URLs.

SIM, roaming, radio, and APN details require ModemManager and NetworkManager access in the environment running Erlang. The Docker webserver can serve the dashboard and internet probes, but cellular details remain unavailable unless the container is explicitly given access to the host modem services.