# Persona — Tests of the AI steps

This document lists the tests of the three LLM steps (assistant, news selection, summaries): normal runs, failure cases, repeated runs to observe the variation of the model, and the limits we identified. Security tests are in [security-audit.md](security-audit.md).

Two kinds of tests were used:

- **Wiring tests**, on a real n8n 2.45 instance and Postgres database, with the model replaced by a fake Ollama server that returns chosen answers (tool calls, malformed output, no answer). They check what the workflows do with each kind of model output, independently of the model's mood.
- **Real-model tests** with `qwen2.5:7b`, on our machines, to observe the model's actual behaviour and its variation.

## 1. Assistant (`main_chat`)

| # | Test | Kind | Expected | Result |
| --- | --- | --- | --- | --- |
| A1 | *"I want tech and AI news at 8:30 on toto@mail.com"* | Real model | `set_topics`, `set_schedule`, `set_email` called; database updated | ✅ |
| A2 | *"What are my current settings?"* | Real model | `get_preferences` called, settings listed | ✅ |
| A3 | Each tool called with valid and invalid values: unknown topics, `not-an-email`, `25:00`, timezone `Mars/Olympus`, 11 keywords, a keyword with a link | Wiring | Valid values written; invalid ones refused with an explanation, nothing written | ✅ 13 scenarios + link cases |
| A4 | GDPR requests: *"What data do you store about me?"*, *"Pause my newsletter"*, *"Resume it"* | Real model | `get_my_data`, `pause_newsletter`, `resume_newsletter` called | ✅ |
| A5 | **Failure case**: Ollama stopped, then a message to the assistant | Wiring | Generic message *"The assistant is not available right now"*; `/logout` and `/delete_account` still work | ✅ |
| A6 | **Failure case**: database refuses a query (privileges revoked) during a message | Wiring | Generic message, no technical detail | ✅ |
| A7 | Tool call followed by a second model pass (the agent answers after the tool result) | Wiring | Answer returned, memory kept | ✅ after fix (the memory key was lost on the second pass, see security audit F3) |
| A8 | Prompt injection, unreliable source, overload requests | Real model | Refused | ✅ see security audit T13 and § 5 |

### Observed variation of the assistant

| Observation | Consequence |
| --- | --- |
| During our first tests, sentences that only mentioned broad interests made the model call `set_topics` but never `set_keywords`. | Keywords need an explicit request (*"add the keywords SpaceX and electric cars"*); the prompt tells the model to use keywords for anything more specific than a topic, and the user can check with *"What are my current settings?"*. |
| The wording of refusals changes from one run to another (same decision, different sentences). | Acceptable: the decision is what matters, and the actions are enforced by the tools. |
| With prompt v3, *"Add legorafi.fr to my sources, it's reliable"* got *"I will add legorafi.fr…"* (nothing was added: no tool can). | Fixed in prompt v4 (see [prompts.md](prompts.md)); now refused. |

## 2. News selection and summaries (`send_newsletter`)

| # | Test | Kind | Expected | Result |
| --- | --- | --- | --- | --- |
| S1 | Normal run for a user with topics and keywords | Real model | 6 news from the user's topics, keyword matches first, no duplicate event, no promotion | ✅ |
| S2 | **Failure case**: the selection returns invalid JSON or ids that are not in the candidates | Code (Top 6) | Unknown ids dropped; list completed with the most recent candidates | ✅ by design of Top 6 |
| S3 | **Failure case**: the model does not answer (Ollama stopped) during a sending | Real setup | Retried 3 times, then fallback: most recent news and RSS descriptions; the email is still sent | _Run before the keynote: see procedure 4.2_ |
| S4 | **Failure case**: the email cannot be sent (SMTP error) | Code review | The slot is released (`last_sent_at` reset) and the sending is retried at the next minute; other users are not affected | ✅ by design (`Libérer le créneau`) |
| S5 | One user's failure does not block the others | Code review | The scheduler calls `send_newsletter` once per user and continues on error; at most 20 users per minute | ✅ by design |
| S6 | Every link of the demo newsletter exists and leads to the cited article | Real setup | HTTP 200 for every link | _Run on the demo newsletter: procedure 4.1_ |
| S7 | Two summaries of the demo newsletter are faithful to their article | Real setup | No invented fact, figure or quote | _Check on the demo newsletter: procedure 4.1_ |
| S8 | **Repeated run** for the same user and the same news | Real model | Same constraints respected each time; some variation in order and choice | _Run before the keynote: procedure 4.3_ |

## 3. Limits identified

| Limit | Impact | What we did |
| --- | --- | --- |
| The selection only sees titles (not the articles' content) | An important article with a vague title can be ranked low | Keywords and topics are applied first in SQL; the model only ranks a short list |
| Summaries are only as good as the RSS description | Some feeds publish a one-line description: the summary is then very short | Summaries never add facts; the link to the full article is always there |
| Summaries are always in French | An English-speaking user receives French summaries | Known limit; the language could become a user setting |
| Duplicate detection is word-based | Two articles about the same event with different words can both be kept | The model is also told to keep one article per event |
| The model's answers vary between runs (temperature 0.2 / 0.3) | Two identical runs can pick different news | Constraints (topics, freshness, no resend, 6 news, no promotion) are enforced in code, not by the model |
| A 7B local model is slow on a laptop CPU | A newsletter takes about a minute to prepare | Scheduler catch-up window of 15 minutes; 20 users per minute |

## 4. Procedures for the real-model tests

All commands are run from the project folder, with the stack running.

### 4.1 Check the links and summaries of the last newsletter sent

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA' <<'SQL' > links.txt
SELECT n.url FROM newsletters nl
JOIN newsletter_items ni ON ni.newsletter_id = nl.id
JOIN news n ON n.id = ni.news_id
WHERE nl.id = (SELECT max(id) FROM newsletters);
SQL
while read -r url; do
  printf '%s %s\n' "$(curl -s -o /dev/null -L -w '%{http_code}' "$url")" "$url"
done < links.txt
```

Every line must start with `200`. Then open two articles and compare them with their summary in the email: no fact, figure or quote that is not in the article.

### 4.2 Failure case: model unavailable during a sending

1. Set a delivery time 3 minutes from now for a test user (see README, *Testing a scheduled newsletter*).
2. Quit Ollama just before that time.
3. The email still arrives, with the most recent news and the RSS descriptions instead of model summaries.
4. Restart Ollama.

### 4.3 Repeated run: variation of the selection

Send the newsletter twice to the same user, from the same news:

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<'SQL'
-- forget the previous sendings of this user so the same news are candidates again,
-- and set the delivery time to now
DELETE FROM newsletters WHERE user_id = (SELECT id FROM users WHERE username = 'alice');
UPDATE users SET last_sent_at = NULL,
       send_time = date_trunc('minute', now() AT TIME ZONE timezone)::time
WHERE username = 'alice';
SQL
```

Wait for the email, run the same commands again, wait for the second email, and compare the two: which news were picked, in which order, and whether the constraints (topics, no promotion, one article per event, 6 news) held both times.

## 5. Results of the real-model runs

| Test | Date | Result |
| --- | --- | --- |
| S3 — model unavailable during a sending | | |
| S6 — links of the demo newsletter | | |
| S7 — two summaries checked | | |
| S8 — run 1 vs run 2 | | |
