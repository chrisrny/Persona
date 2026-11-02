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

2. Create your environment file and replace every `change-me` value:

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

### LLM setup

Persona uses a local model served by Ollama. The model must support tool calling.

**Option A — native Ollama (recommended, required for GPU acceleration on macOS)**

```bash
ollama pull qwen2.5:7b
```

n8n reaches it at `http://host.docker.internal:11434`.

**Option B — Ollama in Docker**

```bash
docker compose --profile ollama up -d
docker compose exec ollama ollama pull qwen2.5:7b
```

n8n reaches it at `http://ollama:11434`.

### Email setup

Newsletters are sent through Gmail SMTP with an app password (your real Gmail password is never used):

1. Enable [2-Step Verification](https://myaccount.google.com/signinoptions/two-step-verification) on the Gmail account.
2. Create an [app password](https://myaccount.google.com/apppasswords) and keep the 16-character value.

## Importing the workflows

_TODO_

## Credentials

Credentials are never stored in this repository. Create them in n8n (**Credentials → Add credential**) with exactly these names so the imported workflows pick them up:

| Name | Type | Values |
| --- | --- | --- |
| `Postgres Persona` | Postgres | Host `postgres`, port `5432`, database `POSTGRES_DB`, user `APP_DB_USER`, password `APP_DB_PASSWORD` (from your `.env`) |
| `LLM` | Ollama | Base URL `http://host.docker.internal:11434` (option A) or `http://ollama:11434` (option B) |
| `SMTP Persona` | SMTP | User: your Gmail address, password: the app password, host `smtp.gmail.com`, port `465`, SSL/TLS enabled |

## Using Persona through the chatbot

_TODO_

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

_TODO_

## Project structure

```txt
persona/
├── workflows/          # n8n workflows (anonymized JSON exports)
├── db/
│   ├── init.sql        # Database schema
│   └── app-role.sh     # Least-privilege role used by n8n
├── docs/               # Architecture, GDPR, security audit
├── keynote/            # Presentation material
├── docker-compose.yml  # n8n + Postgres
└── .env.example        # Environment template
```
