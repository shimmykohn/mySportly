# OpenAI Decisions API: what the app relies on

Read from the official reference on 2026-11-09: <https://developers.openai.com/api/reference/resources/decisions/methods/create/index.md>. Public beta since 2026-10-06.

## Request

`POST https://api.openai.com/v1/decisions` with `Authorization: Bearer <key>` and `Content-Type: application/json`.

| Field | Notes |
|---|---|
| `model` | Required. Only `gpt-6-luna`. |
| `input` | Required. A string (≤ 10 MiB) or an array of messages. |
| `questions` | Required. 1–400 questions; answers come back in the same order. |
| `prompt_cache_key` | Optional, ≤ 64 chars. |
| `safety_identifier` | Optional, ≤ 128 chars, opaque end-user ID. |

Question types (each has `type`, `instructions` and an optional `name`):

- `predicate`: the probability that a statement about the input is true.
- `choice`: `choices` is 2–255 unique `{ "value": string|bool, "description"?: string }`.
- `score`: `levels` is 2–10 `{ "label": string, "description"?: string }`.

## Response

`{ "model", "answers": [...], "usage": {...} }`. Answers are in question order and carry `name`.

- predicate: `{ "type": "predicate", "name", "probability" }`
- choice: `{ "type": "choice", "name", "choice", "confidence", "probabilities": [{ "value", "probability" }] }`
- score: `{ "type": "score", "name", "score", "confidence", "probabilities": [{ "label", "value", "probability" }] }`
- refusal: `{ "type": "refusal", "name" }`. Any question can be refused while others are answered; it is not an HTTP error.

Error format and rate limits are not documented on that page; the client treats any non-2xx as a retryable failure and keeps local results.

## Example

```json
{"model":"gpt-6-luna","input":"The package arrived with a broken screen.","questions":[{"type":"predicate","name":"damaged","instructions":"Does the customer report a damaged item?"}]}
```

```json
{"model":"gpt-6-luna","answers":[{"type":"predicate","name":"damaged","probability":0.95}],"usage":{"input_tokens":42,"input_tokens_details":{"cached_tokens":0,"cache_write_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":42}}
```
