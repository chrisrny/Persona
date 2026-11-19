#!/bin/bash
# Creates the least-privilege role used by the n8n workflows.
# The admin role (POSTGRES_USER) is only used by the container itself.
set -e

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -v app_user="$APP_DB_USER" \
     -v app_password="$APP_DB_PASSWORD" \
     -v db_name="$POSTGRES_DB" <<-'EOSQL'
    CREATE ROLE :"app_user" LOGIN PASSWORD :'app_password';

    GRANT CONNECT ON DATABASE :"db_name" TO :"app_user";
    GRANT USAGE ON SCHEMA public TO :"app_user";

    -- Data tables: read/write, no schema changes
    GRANT SELECT, INSERT, UPDATE, DELETE
        ON users, user_topics, sessions, news, newsletters, newsletter_items
        TO :"app_user";
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"app_user";

    -- The topic taxonomy is read-only for the workflows
    GRANT SELECT ON topics TO :"app_user";
EOSQL
