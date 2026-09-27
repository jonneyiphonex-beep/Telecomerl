# Telecomerl

Telecomerl includes an Erlang HTTP server for the network diagnostics dashboard.

## Run the web server

### Linux, macOS, and Windows with Docker Desktop

Install Docker Desktop with Compose, then run this from the project directory:

```sh
docker compose up --build
```

Open [http://localhost:8080](http://localhost:8080). Stop the foreground server with Ctrl+C. Set `PORT` or `CHECK_INTERVAL_MS` in a `.env` file beside `compose.yaml` to override the defaults.

### Native Erlang/OTP

Install Erlang/OTP. On Linux and macOS run:

```sh
./run.sh
```

On Windows run `run.bat` from Command Prompt or PowerShell. The launcher compiles the source before starting the server. `make run` remains available on systems with GNU Make.

### Real device checks

For SIM, roaming, and APN checks against a real device, run the native Erlang launcher on the Linux host with the modem attached and managed by ModemManager and NetworkManager:

```sh
make device
```

Windows and macOS can run the dashboard and internet probes, but this implementation cannot inspect their cellular modem interfaces. Docker is isolated from host modem services and likewise reports cellular status unavailable unless host modem services are explicitly integrated.

For Linux systems with Erlang but without GNU Make, start the app directly with `./run.sh`. For Linux systems without Erlang, `docker compose up --build` runs the dashboard and internet probes.

The server serves the dashboard at `/` and exposes `GET /api/status` and `GET /api/refresh`. `CHECK_INTERVAL_MS` controls automatic checks (5,000 to 300,000 ms); `TELECOM_PROBE_URLS` accepts semicolon-separated HTTP or HTTPS URLs.