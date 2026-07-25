# Contributing

Contributions are welcome.

## Local setup

1. Fork and clone the repository.
2. Create a branch from `main`.
3. Make a focused change.
4. Run the test suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

5. Open a pull request describing the problem, solution and validation.

## Guidelines

- keep compatibility with Windows PowerShell 5.1;
- do not add external dependencies without a strong reason;
- never commit credentials, cookies or real profile snapshots;
- use temporary directories in tests;
- preserve user data and fail safely before destructive operations;
- document user-visible behavior.

## Bug reports

Include Windows version, installed OpenAI package name/version, command used
and sanitized output. Never attach `auth.json` or files from a profile.
