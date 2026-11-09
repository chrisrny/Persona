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

The script creates the n8n credentials from your `.env`, imports every file of `workflows/` and publishes them. It can be run again after pulling new versions of the workflows (existing ones are overwritten).

> After the restart, n8n needs about 20 seconds to switch to the newly published versions. Messages sent right away may still be handled by the previous version.

| Workflow | Role |
| --- | --- |
| `Persona - main_chat` | Chat entry point: session check, routing, AI agent |
| `Persona - auth` | Sign-up, login and sessions (sub-workflow, no LLM involved) |
| `Persona - user_tools` | The only actions the agent can perform on user data: read and update the user's preferences (sub-workflow) |

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

| Setting | Accepted values |
| --- | --- |
| Topics | `tech`, `ai`, `science`, `economy`, `sport`, `culture`, `health`, `environment`, `world` (the assistant maps your words to this list) |
| Keywords | Up to 10, 40 characters each |
| Email | A valid email address |
| Delivery time | Every day at `HH:MM` (24h), in your timezone |
| Timezone | An [IANA name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones), `Europe/Paris` by default |

The assistant runs on the local Ollama model, so the first answer can take a few seconds while the model loads.

## Testing a scheduled newsletter

_TODO_

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

_TODO_

## Security

- **Authentication happens before the AI.** Sign-up, login and session checks are plain n8n nodes and SQL queries: the LLM never sees credentials and cannot be talked into skipping authentication.
- **Passwords** are hashed with bcrypt (`pgcrypto`) and never stored or returned in clear text.
- **Brute force**: 5 failed logins lock the account for 15 minutes; error messages never reveal whether a username exists.
- **SQL injection**: every query uses bound parameters (`$1`, `$2`...).
- **The AI cannot reach other users' data.** The agent's tools never take a user id: `main_chat` injects the id of the authenticated session into every tool call, so even a manipulated model can only read or change the current user's settings. Every value the model provides is validated again (format, length, existing topic, real IANA timezone) before reaching the database.
- **Separate conversation memory per user**: the memory is keyed on the chat session *and* the user, so after `/logout` and a login with another account in the same chat, the new user never sees the previous conversation.
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
├── docs/               # Architecture, GDPR, security audit
├── keynote/            # Presentation material
├── docker-compose.yml  # n8n + Postgres
└── .env.example        # Environment template
```
