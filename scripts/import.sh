#!/bin/sh
# Imports Persona credentials and workflows into n8n, then publishes the workflows.
# Run inside the n8n container:
#   docker compose exec n8n sh /scripts/import.sh
#   docker compose restart n8n
# Safe to run again: existing credentials and workflows are overwritten.
set -e

CREDENTIALS_FILE="$(mktemp)"
trap 'rm -f "$CREDENTIALS_FILE"' EXIT

# Credentials are built from the container environment (.env), never stored in the repo.
node -e '
const env = process.env;
const credentials = [
  {
    id: "prsnPostgresCred",
    name: "Postgres Persona",
    type: "postgres",
    data: {
      host: "postgres",
      port: 5432,
      database: env.POSTGRES_DB,
      user: env.APP_DB_USER,
      password: env.APP_DB_PASSWORD,
      ssl: "disable",
    },
  },
  {
    id: "prsnOllamaCred01",
    name: "LLM",
    type: "ollamaApi",
    data: { baseUrl: env.OLLAMA_BASE_URL },
  },
  {
    id: "prsnSmtpCred0001",
    name: "SMTP Persona",
    type: "smtp",
    data: {
      user: env.SMTP_USER,
      password: env.SMTP_PASSWORD,
      host: "smtp.gmail.com",
      port: 465,
      secure: true,
    },
  },
];
require("fs").writeFileSync(process.argv[1], JSON.stringify(credentials));
' "$CREDENTIALS_FILE"

n8n import:credentials --input="$CREDENTIALS_FILE"
n8n import:workflow --separate --input=/workflows

# Sub-workflows first, then the workflows that call them, then the triggers
for id in \
  prsnAuth00000001 \
  prsnUserTools001 \
  prsnSendNewsl001 \
  prsnMainChat0001 \
  prsnScheduler001 \
  prsnFetchNews001
do
  n8n publish:workflow --id="$id"
done

# First news fetch, so a newsletter can be tested right away (fetch_news then runs
# every hour). Another task broker port is used because n8n is already running.
echo "Fetching news for the first time (this can take a minute)..."
if N8N_RUNNERS_BROKER_PORT=5690 n8n execute --id=prsnFetchNews001 > /dev/null 2>&1; then
  echo "News fetched."
else
  echo "Warning: the first news fetch failed. Run it later with:"
  echo "  docker compose exec -e N8N_RUNNERS_BROKER_PORT=5690 n8n n8n execute --id=prsnFetchNews001"
fi

echo "Done. Restart n8n to apply: docker compose restart n8n"
