@echo off
setlocal
pushd "%~dp0"

where erlc >nul 2>nul || (
  echo Erlang/OTP compiler erlc is required. Install Erlang/OTP or use Docker Compose.
  popd
  exit /b 1
)
where erl >nul 2>nul || (
  echo Erlang/OTP runtime erl is required. Install Erlang/OTP or use Docker Compose.
  popd
  exit /b 1
)

if not exist "_build\ebin" mkdir "_build\ebin"
for %%F in (src\*.erl) do (
  erlc -Werror -o "_build\ebin" "%%F"
  if errorlevel 1 goto compile_error
)
copy /Y "src\telecomerl.app.src" "_build\ebin\telecomerl.app" >nul
if errorlevel 1 goto compile_error

set "TELECOM_STATIC_DIR=%CD%\static"
erl -pa "_build\ebin" -noshell -eval "telecomerl:start(), receive stop -> ok end."
set "ERL_STATUS=%ERRORLEVEL%"
popd
exit /b %ERL_STATUS%

:compile_error
popd
exit /b 1