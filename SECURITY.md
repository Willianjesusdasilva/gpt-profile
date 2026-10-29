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

## Portable account backups

`backup -IncludeProfiles` creates a password-encrypted `.gptbackup` containing
session snapshots and tokens. Treat it as secret material. Transfer only between
your trusted machines; never publish it. Use a strong, unique password. JSON
repository backups contain no app credentials. The encrypted format uses AES-256-CBC
with encrypt-then-HMAC-SHA256 and PBKDF2-SHA256 (210,000 iterations), random salt
and IV. Wrong passwords or altered ciphertext are rejected before importing files.
Imported profiles are local plaintext snapshots, protected by your Windows account.
Expired sessions and OS-bound credentials can still require a new login.
