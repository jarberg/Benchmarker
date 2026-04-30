@echo off
REM Local launcher for the Phoenix + Ash server (Windows).
REM Assumes: Erlang/OTP, Elixir, Node.js, and Postgres are installed.

setlocal
cd /d %~dp0

if not exist deps (
  echo Installing Elixir deps...
  call mix deps.get || goto :error
)

if not exist assets\node_modules (
  echo Installing JS deps...
  pushd assets
  call npm install || goto :pop_error
  popd
)

echo Running migrations + seeds...
call mix ash.setup || goto :error

echo Starting Phoenix on http://localhost:4000 ...
call mix phx.server
goto :eof

:pop_error
popd
:error
echo.
echo *** Launch failed (errorlevel %errorlevel%). ***
exit /b %errorlevel%
