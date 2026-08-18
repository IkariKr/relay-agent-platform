@echo off
REM Thin Relay test stub launcher for the "antigravity" backend.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stub-cli.ps1" %*
