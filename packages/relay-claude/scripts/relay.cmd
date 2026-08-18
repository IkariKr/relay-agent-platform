@echo off
REM Relay canonical launcher (Thin Relay v2 SOP §4.0).
REM Pure launcher: locates and invokes scripts/relay.ps1 only; no business logic here.
REM Note: relay.ps1 is invoked via powershell -File so that the `--` prompt separator
REM and repeated `--passthrough <token>` are preserved verbatim.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0relay.ps1" %*
exit /b %ERRORLEVEL%
