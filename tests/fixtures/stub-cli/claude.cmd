@echo off
REM Thin Relay test stub launcher for the "claude" backend.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stub-cli.ps1" %*
