# Persona — GDPR compliance

This document describes which personal data Persona processes, why, for how long, who receives it, and how users exercise their rights. It reflects the workflows in `workflows/` and the schema in `db/init.sql`.

Persona is self-hosted: whoever runs the stack (for this project, the client) is the **data controller**. All data stays in the Postgres database and the n8n instance of the deployment.

## 1. Personal data inventory

| Data | Where | Purpose | Retention |
| --- | --- | --- | --- |
| Username | `users.username` | Identify the account in the chat | Until the account is deleted |
| Password | `users.password_hash` (bcrypt, cost 10) | Authentication. The clear-text password is never stored | Until the account is deleted |
| Email address | `users.email` | Deliver the newsletter | Until changed or the account is deleted |
| Topics, keywords | `user_topics`, `users.keywords` | Select the news for the user | Until changed or the account is deleted |
| Delivery time, timezone | `users.send_time`, `users.timezone` | Send at the chosen time | Until changed or the account is deleted |
| Subscription status | `users.active` | Pause / unsubscribe | Until the account is deleted |
| Consent date | `users.consent_at` | Proof of consent | Until the account is deleted |
| Account dates, last sending | `users.created_at`, `updated_at`, `last_sent_at` | Operation, no double sending | Until the account is deleted |
| Failed logins, lock | `users.failed_login_attempts`, `locked_until` | Brute-force protection | Reset at the next successful login |
| Chat session | `sessions` (chat session id ↔ user) | Keep the user logged in | 2 hours after the last message; expired rows are purged at each login, the row is deleted at `/logout` |
| Newsletter history | `newsletters`, `newsletter_items` | Never send the same news twice; right of access | Until the account is deleted |
| Assistant conversation | n8n process memory (last 10 messages, per session and user) | Context for the assistant | Until n8n restarts. Never written to disk |

Not personal data: the news articles (`news`, public RSS content), purged after 7 days unless they were part of a sent newsletter.

**Data minimisation**: Persona stores no real name, no postal address, no phone number, no IP address and no tracking data. Only what the newsletter needs.

### What is never stored

- **Passwords in clear text**, anywhere. The `main_chat`, `auth` and `user_tools` workflows do not save their executions, because chat messages can contain a password (`/login`, `/register`, `/delete_account`).
- **Passwords in the AI**: authentication and account deletion are plain n8n nodes and SQL. The language model never receives a password.

## 2. Legal basis

- **Consent** (GDPR art. 6(1)(a)): an account can only be created with `/register <username> <password> accept`, right after this notice is shown in the chat:

  > **Privacy:** Persona only stores your username, a hashed password, your email, your topics and your preferred delivery time, in order to send you your newsletter. You can view, pause or delete your data at any time from this chat. Adding `accept` to the register command means you agree to this.

  Without the word `accept`, no account is created. The consent date is stored in `users.consent_at`.
- **Performance of the service** the user asked for (art. 6(1)(b)): the data is only used to build and send that user's newsletter.

## 3. Recipients and processors

| Recipient | Data | Why | Notes |
| --- | --- | --- | --- |
| Ollama (local) | Chat messages, keywords, news titles | Assistant, news selection, summaries | Runs on the same machine. **No data is sent to an external AI provider.** |
| Gmail SMTP (Google) | Email address, newsletter content | Email delivery | Google acts as a processor. For an EU production deployment, prefer an SMTP provider hosted in the EU. |
| RSS sources | None | Fetching public news | Outbound requests only, no user data is sent. |

Personal data is not sold, shared or used for advertising.

## 4. User rights

Every right can be exercised directly in the chat, after logging in.

| Right | How |
| --- | --- |
| **Access** (art. 15) | Ask *"What data do you store about me?"*. The assistant returns everything stored: account, consent date, settings, number of newsletters received, last sending, active sessions. The password is only mentioned as an irreversible hash. |
| **Rectification** (art. 16) | Ask the assistant to change the email, topics, keywords, time or timezone. |
| **Objection / unsubscribe** (art. 21) | *"Pause my newsletter"* or *"Unsubscribe me"*: no more emails, settings kept. *"Resume my newsletter"* starts them again. Every email reminds the user that they can unsubscribe from the chat. |
| **Erasure** (art. 17) | Type `/delete_account <password>`. See below. |
| **Withdrawing consent** (art. 7(3)) | Same as erasure: deleting the account withdraws consent and removes the data. Pausing stops the processing for sending while keeping the account. |

### Account deletion

`/delete_account <password>` is handled by n8n nodes and SQL, never by the AI:

1. The password is checked again by the database, so a stolen session cannot erase an account.
2. One `DELETE FROM users` removes the user. Thanks to `ON DELETE CASCADE`, the sessions, followed topics and newsletter history are removed in the same transaction.
3. Wrong passwords count as failed logins: after 5, the account is locked for 15 minutes and all its sessions are closed.

What remains after deletion: nothing linked to the person in the database. The news articles stay (not personal data). The assistant's in-memory conversation disappears at the next n8n restart.

## 5. Security of processing (art. 32)

Summary (details and tests in [security-audit.md](security-audit.md)):

- authentication outside the AI, bcrypt hashes, 2-hour sessions, lock after 5 failed attempts;
- the AI has no tool able to reach another user's data or delete an account;
- parameterized SQL everywhere, least-privilege database role;
- message length and rate limits, generic error messages;
- services bound to `127.0.0.1`, secrets only in `.env` (never committed).

## 6. Limits and what a production deployment would add

- **Privacy policy page and controller contact**: in this project the notice lives in the chat. A real deployment needs a public privacy policy with the controller's identity and contact (and a DPO if required).
- **Inactive accounts**: there is no automatic deletion yet. A production version would delete or warn accounts inactive for, for example, 12 months.
- **Execution history of the sending workflows**: `fetch_news`, `send_newsletter` and `scheduler` keep n8n's default execution history, which includes usernames and email addresses (pruned by n8n after 14 days by default). Setting them to *Do not save* like the chat workflows would remove this copy.
- **Email provider**: replace Gmail with an EU-hosted SMTP provider and sign a data processing agreement.
- **Data portability** (art. 20): the access answer is structured, but a downloadable JSON export would make portability explicit.
- **Breach procedure**: document who is notified, and how the supervisory authority (CNIL in France) is informed within 72 hours.
