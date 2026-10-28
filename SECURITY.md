# Security Policy

## Supported versions

Only the **latest release** of Zeph#Ink receives security fixes.

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

Instead, report it privately through GitHub:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the issue, how to reproduce it, and its potential impact.

You'll get an acknowledgment within a few days. Once a fix is released, you'll be credited in the release notes (unless you'd rather stay anonymous).

## Scope

Zeph#Ink never goes online: it runs in the macOS App Sandbox without the network entitlement, and it can open and save only the files you pick (plus the autosaves and versions macOS keeps for them). It has no accounts, no telemetry and no update checks.

### Of particular interest

- A way for a document's content to run code, reach the network or read files you didn't open
- A way for Zeph#Ink to change a file you didn't edit
- Issues with the app's sandbox entitlements or code signing
- Tampering with release artifacts
