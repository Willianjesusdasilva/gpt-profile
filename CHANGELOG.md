# Changelog

All notable changes will be documented in this file.

## [Unreleased]

### Added

- local profile capture and switching;
- `gpt-profile open <name>` command;
- automatic launch of the selected profile;
- support for the Codex desktop `auth.json`;
- shared local workspace;
- profile listing and status diagnostics;
- dependency-free PowerShell installer;
- optional uninstaller that preserves profiles by default;
- temporary-directory test suite.

### Security

- profile names are validated;
- destructive removal requires `-Force`;
- profile restoration requires a matching saved credential on Codex desktop;
- sensitive runtime files are ignored by Git.
