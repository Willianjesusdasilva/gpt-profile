# Security policy

## Sensitive local data

`gpt-profile` stores snapshots containing cookies and authentication tokens.
Treat `%USERPROFILE%\gpt-profile` as secret material.

Do not:

- commit or upload this directory;
- sync it to cloud storage;
- send profiles to another person;
- run the tool on a shared or untrusted computer.

If a snapshot is exposed, terminate the affected OpenAI sessions and
authenticate again.

## Reporting a vulnerability

Please do not publish exploitable details in a public issue. Use GitHub's
private vulnerability reporting feature in the repository Security tab.

Include:

- affected version or commit;
- Windows and app versions;
- reproduction steps;
- expected and observed behavior;
- impact assessment.

Never include real tokens, cookies, `auth.json`, or profile snapshots.

## Supported versions

Until the first stable release, only the latest commit on `main` is supported.
