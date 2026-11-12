# Persona

A UI-less AI news aggregator, driven by a chatbot and built with n8n.

Users talk to a single chat interface to create an account, choose their topics of interest, give their email address and pick a time slot. Persona then fetches fresh news from multiple sources, selects the stories relevant to each user and emails them a personalized newsletter (links + summaries) at the chosen time.

## Table of contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Importing the workflows](#importing-the-workflows)
4. [Credentials](#credentials)
5. [Using Persona through the chatbot](#using-persona-through-the-chatbot)
6. [Testing a scheduled newsletter](#testing-a-scheduled-newsletter)
7. [Data storage](#data-storage)
8. [GDPR](#gdpr)
9. [Security](#security)
10. [Project structure](#project-structure)

## Requirements

- [Docker](https://docs.docker.com/get-docker/) with Docker Compose v2
- [Ollama](https://ollama.com/download) with the `qwen2.5:7b` model (see [LLM setup](#llm-setup))
- A Gmail account with 2-Step Verification enabled, to send the newsletters (see [Email setup](#email-setup))

## Installation

1. Clone the repository and enter it:

   ```bash
   git clone <repository-url> persona
   cd persona
   ```

2. Create your environment file and fill it in (every `change-me` value, your Gmail address and `OLLAMA_BASE_URL`, see [LLM setup](#llm-setup) and [Email setup](#email-setup)):

   ```bash
   cp .env.example .env
   openssl rand -hex 32   # use the output as N8N_ENCRYPTION_KEY
   ```

3. Start the stack:

   ```bash
   docker compose up -d
   ```

   On first start, Postgres creates the database schema (`db/init.sql`) and a least-privilege role for the workflows (`db/app-role.sh`).

4. Open n8n at <http://localhost:5678> and create the owner account.

> To reset everything (database included): `docker compose down -v`, then `docker compose up -d`.

> **The database schema and the `APP_DB_USER` role are only created on the very first start**, when the Postgres volume is empty. If you change `POSTGRES_*` or `APP_DB_*` in `.env` afterwards, or if the first start failed, recreate the database volume (this deletes Persona's data, not your n8n account):
>
> ```bash
> docker compose down
> docker volume rm persona_postgres_data   # name shown by: docker volume ls
> docker compose up -d
> docker compose exec n8n sh /scripts/import.sh
> docker compose restart n8n
> ```
>
> If the chat answers "Error in workflow" with `password authentication failed for user "persona_app"`, this is the cause.

### LLM setup

Persona uses a local model served by Ollama. The model must support tool calling.

**Option A — native Ollama (recommended, required for GPU acceleration on macOS)**

```bash
ollama pull qwen2.5:7b
```

Set `OLLAMA_BASE_URL=http://host.docker.internal:11434` in `.env`.

**Option B — Ollama in Docker**

```bash
docker compose --profile ollama up -d
docker compose exec ollama ollama pull qwen2.5:7b
```

Set `OLLAMA_BASE_URL=http://ollama:11434` in `.env`.

### Email setup

Newsletters are sent through Gmail SMTP with an app password (your real Gmail password is never used):

1. Enable [2-Step Verification](https://myaccount.google.com/signinoptions/two-step-verification) on the Gmail account.
2. Create an [app password](https://myaccount.google.com/apppasswords).
3. Set `SMTP_USER` (the Gmail address) and `SMTP_PASSWORD` (the app password, without spaces) in `.env`.

## Importing the workflows

Once n8n is running and the owner account is created, import the credentials and the workflows, then restart n8n:

```bash
docker compose exec n8n sh /scripts/import.sh
docker compose restart n8n
```

The script creates the n8n credentials from your `.env`, imports every file of `workflows/`, publishes them and runs a first news fetch. It can be run again after pulling new versions of the workflows (existing ones are overwritten).

> After the restart, n8n needs about 20 seconds to switch to the newly published versions. Messages sent right away may still be handled by the previous version.

| Workflow | Role |
| --- | --- |
| `Persona - main_chat` | Chat entry point: session check, routing, AI agent |
| `Persona - auth` | Sign-up, login and sessions (sub-workflow, no LLM involved) |
| `Persona - user_tools` | The only actions the agent can perform on user data: read and update preferences, export all personal data, pause or resume the newsletter (sub-workflow) |
| `Persona - fetch_news` | Every hour: fetches the RSS sources, cleans and stores the news, purges news older than 7 days |
| `Persona - scheduler` | Every minute: finds the users whose delivery time has just arrived in their timezone and starts their newsletter |
| `Persona - send_newsletter` | Selects the news for one user, summarizes them and sends the email (sub-workflow) |

## Credentials

Credentials are never stored in this repository: `scripts/import.sh` builds them from `.env`.

| Name | Type | Built from |
| --- | --- | --- |
| `Postgres Persona` | Postgres | `POSTGRES_DB`, `APP_DB_USER`, `APP_DB_PASSWORD` (host `postgres`, port `5432`) |
| `LLM` | Ollama | `OLLAMA_BASE_URL` |
| `SMTP Persona` | SMTP | `SMTP_USER`, `SMTP_PASSWORD` (host `smtp.gmail.com`, port `465`, SSL/TLS) |

To change one later, edit `.env`, run `docker compose up -d` to reload the environment, then run the import script again.

## Using Persona through the chatbot

Open the chat at <http://localhost:5678/webhook/b6f1c6d2-6a51-4c1e-9a43-7d2f0e3c9a11/chat>.

| Command | Effect |
| --- | --- |
| `/register <username> <password> accept` | Creates an account and logs you in. `accept` is your explicit consent to the privacy notice shown in the chat. |
| `/login <username> <password>` | Logs you in |
| `/logout` | Ends your session |
| `/delete_account <password>` | Permanently deletes your account and all your data (see [GDPR](#gdpr)) |

Messages are limited to 1,000 characters and 20 per minute per chat.

- Username: 3 to 32 letters, digits or underscores (case-insensitive).
- Password: 8 to 72 characters, no spaces.
- A session lasts 2 hours after your last message.
- After 5 failed logins, the account is locked for 15 minutes.

Once logged in, just talk to the assistant in natural language, for example:

- *"I'm interested in tech, AI and climate news"*
- *"Add the keywords SpaceX and electric cars"*
- *"Send it to me at me@example.com every day at 8:30"*
- *"I live in New York"* (timezone `America/New_York`)
- *"What are my current settings?"*
- *"What data do you store about me?"*
- *"Pause my newsletter"* / *"Unsubscribe me"* / *"Resume my newsletter"*

| Setting | Accepted values |
| --- | --- |
| Topics | `tech`, `ai`, `science`, `economy`, `sport`, `culture`, `health`, `environment`, `world` (the assistant maps your words to this list) |
| Keywords | Up to 10, 40 characters each, no links or website addresses |
| Email | A valid email address |
| Delivery time | Every day at `HH:MM` (24h), in your timezone. The newsletter is daily |
| Timezone | An [IANA name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones), `Europe/Paris` by default |

The assistant runs on the local Ollama model, so the first answer can take a few seconds while the model loads.

## Testing a scheduled newsletter

The newsletter is sent **every day** at the time chosen by the user, in their timezone. To see one arrive in a few minutes:

1. **Check that news are available.** The import script fetches them once, then `fetch_news` runs every hour. To count them, or to fetch again right away:

   ```bash
   docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT topic_slug, count(*) FROM news GROUP BY 1"'
   docker compose exec -e N8N_RUNNERS_BROKER_PORT=5690 n8n n8n execute --id=prsnFetchNews001
   ```

2. **Create an account and set it up in the chat**, with a delivery time **3 minutes from now** (24h format, in your timezone):

   ```text
   /register alice MyPassw0rd accept
   I'm interested in tech and AI. Send it to me at <your email> every day at 14:03
   What are my current settings?
   ```

   The default timezone is `Europe/Paris`. If you are elsewhere, also say for example *"I live in New York"*.

3. **Wait.** The scheduler checks every minute. Once the time is reached, selecting and summarizing the news with the local model takes about a minute, then the email is sent from the Gmail address of `SMTP_USER`. Check the spam folder too.

4. **Test again.** Each user receives at most one newsletter per day. To send another one today, either create a new account, or reset the last sending and choose a new time:

   ```bash
   docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<'SQL'
   UPDATE users SET last_sent_at = NULL WHERE username = 'alice';
   SQL
   ```

If no email arrives:

| Check | How |
| --- | --- |
| The time is right | *"What are my current settings?"* shows the time and timezone. A time missed by less than 15 minutes is still sent (catch-up window). |
| There are recent news for the chosen topics | Query above. No newsletter is sent when no news of the last 48 hours matches the user's topics. |
| The newsletter is not paused | The settings show `newsletter_active: true` (*"Resume my newsletter"* otherwise). |
| The workflows ran | In n8n, open **Persona - scheduler** and **Persona - send_newsletter**, tab **Executions**. |
| Ollama and Gmail work | `ollama list` shows `qwen2.5:7b`; `SMTP_PASSWORD` is a Gmail app password, without spaces. |

## Data storage

All data lives in the `persona` Postgres database:

| Table | Content |
| --- | --- |
| `topics` | Closed list of topics shared by users and news |
| `users` | Account, bcrypt password hash, email, keywords, send time, timezone, consent date |
| `user_topics` | Topics followed by each user |
| `sessions` | Chat session → authenticated user, with expiration |
| `news` | News fetched from RSS sources, deduplicated by URL |
| `newsletters`, `newsletter_items` | Newsletters sent and the news they contained |

## GDPR

Persona is designed to be usable in the European Union. Full details (data inventory, retention, processors, limits): [docs/rgpd.md](docs/rgpd.md).

| Principle | How Persona applies it |
| --- | --- |
| **Explicit consent** | An account can only be created with `/register <username> <password> accept`, after the privacy notice is shown in the chat. The consent date is stored (`users.consent_at`). |
| **Data minimisation** | Only what the newsletter needs is stored: username, password hash, email, topics, keywords, delivery time, timezone. No real name, no IP address, no tracking. |
| **Purpose limitation** | The data is only used to build and send the user's newsletter. |
| **No third-party processing** | The LLM runs locally (Ollama): conversations and preferences are never sent to an external AI provider. |
| **Right of access** | Ask the assistant *"What data do you store about me?"*: it returns everything stored about you (the password only exists as an irreversible bcrypt hash). |
| **Right to rectification** | Every setting can be changed at any time through the chat. |
| **Right to object / unsubscribe** | *"Pause my newsletter"* stops all emails immediately while keeping the settings; *"Resume my newsletter"* starts them again. |
| **Right to erasure** | `/delete_account <password>` deletes the account and, through `ON DELETE CASCADE`, its sessions, topics and newsletter history in a single transaction. The password is asked again so a stolen session cannot erase an account. |
| **Security of processing** | See [Security](#security). |

Account deletion is a plain chat command handled by n8n nodes and SQL, never by the AI: the password is checked by the database and never reaches the language model. Wrong passwords count as failed logins (5 failures lock the account for 15 minutes and close all its sessions).

News articles are not personal data and are kept after an account is deleted. The assistant's short-term conversation memory lives in the n8n process only (last 10 messages per session) and is cleared when n8n restarts.

## Security

Threats, tests and known limits are documented in [docs/security-audit.md](docs/security-audit.md).

- **Authentication happens before the AI.** Sign-up, login and session checks are plain n8n nodes and SQL queries: the LLM never sees credentials and cannot be talked into skipping authentication.
- **Passwords** are hashed with bcrypt (`pgcrypto`) and never stored or returned in clear text.
- **Brute force**: 5 failed logins lock the account for 15 minutes; error messages never reveal whether a username exists.
- **SQL injection**: every query uses bound parameters (`$1`, `$2`...).
- **The AI cannot reach other users' data.** The agent's tools never take a user id: `main_chat` injects the id of the authenticated session into every tool call, so even a manipulated model can only read or change the current user's settings. Every value the model provides is validated again (format, length, existing topic, real IANA timezone) before reaching the database.
- **Separate conversation memory per user**: the memory is keyed on the chat session *and* the user, so after `/logout` and a login with another account in the same chat, the new user never sees the previous conversation.
- **No destructive action through the AI**: deleting an account requires the `/delete_account <password>` command, which bypasses the assistant entirely.
- **Message limits**: before anything else, `main_chat` rejects empty messages and messages over 1,000 characters, and applies rate limits (20 messages per minute per chat session, 200 per minute for the whole instance, to protect the local model).
- **No technical details in errors**: if the database or the language model fails, the user gets a generic message ("something went wrong" / "the assistant is not available right now") instead of an n8n error. `/logout` and `/delete_account` keep working when the model is down.
- **Model overload limits**: the assistant's answers are capped at 512 tokens and 6 tool steps per message; the newsletter volume (one per day, one address, a fixed number of news) is enforced in code and SQL, never chosen by the model.
- **Curated sources only**: news only come from the fixed list of RSS feeds in `fetch_news`. Users cannot add a source, and keywords cannot contain links or website addresses.
- **Prompt-injection resistant assistant**: the system prompt treats user messages and tool results as data, never as instructions, refuses to reveal its instructions and cannot switch accounts. Even if the model were fooled, it has no tool able to reach another user or delete an account.
- **Narrow assistant**: the system prompt limits the assistant to newsletter settings and tells it to ignore requests to change its rules or play another role.
- **Least privilege**: workflows connect with `APP_DB_USER`, which can read and write data but cannot change the schema or the topic list.
- **No password in the execution history**: `main_chat`, `auth` and `user_tools` do not save their executions, since chat messages may contain passwords. n8n flags these runs as deleted right away and purges them from its database on its next pruning cycle. To debug, temporarily set **Workflow settings → Save successful production executions** back to *Save*.

## Project structure

```txt
persona/
├── workflows/          # n8n workflows (anonymized JSON exports)
├── db/
│   ├── init.sql        # Database schema
│   └── app-role.sh     # Least-privilege role used by n8n
├── scripts/
│   └── import.sh       # Imports credentials and workflows into n8n
├── docs/
│   ├── rgpd.md         # GDPR: data, retention, rights
│   └── security-audit.md  # Threats, tests, known limits
├── keynote/            # Presentation material
├── docker-compose.yml  # n8n + Postgres
└── .env.example        # Environment template
```
