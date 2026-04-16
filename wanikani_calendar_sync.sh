#!/bin/sh
# wanikani_calendar_sync.sh
# Fetches the next WaniKani review time and upserts a single Google Calendar event.
# Uses a fixed event ID so re-runs silently overwrite — no duplicates ever.
#
# Required env vars:
#   WANIKANI_API_TOKEN   — your WaniKani v2 API token
#   GCAL_CLIENT_ID       — OAuth2 client ID (Desktop app type)
#   GCAL_CLIENT_SECRET   — OAuth2 client secret
#   GCAL_REFRESH_TOKEN   — long-lived refresh token (from get_refresh_token.py)
#   GCAL_CALENDAR_ID     — target calendar ID (yourname@gmail.com for primary)

set -e

# ─── 0. Sanity checks ────────────────────────────────────────────────────────

: "${WANIKANI_API_TOKEN:?Need WANIKANI_API_TOKEN}"
: "${GCAL_CLIENT_ID:?Need GCAL_CLIENT_ID}"
: "${GCAL_CLIENT_SECRET:?Need GCAL_CLIENT_SECRET}"
: "${GCAL_REFRESH_TOKEN:?Need GCAL_REFRESH_TOKEN}"
: "${GCAL_CALENDAR_ID:?Need GCAL_CALENDAR_ID}"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd"; exit 1; }
done

# ─── 1. Fetch WaniKani summary ───────────────────────────────────────────────

echo "Fetching WaniKani summary..."

SUMMARY=$(curl -sf \
  -H "Authorization: Bearer ${WANIKANI_API_TOKEN}" \
  -H "Wanikani-Revision: 20170710" \
  "https://api.wanikani.com/v2/summary")

NEXT_REVIEW_AT=$(echo "$SUMMARY" | jq -r '.data.next_reviews_at // empty')

if [ -z "$NEXT_REVIEW_AT" ]; then
  echo "No upcoming reviews scheduled. Nothing to do."
  exit 0
fi

# Count items in the next review bucket
REVIEW_COUNT=$(echo "$SUMMARY" | jq --arg t "$NEXT_REVIEW_AT" '
  .data.reviews[] | select(.available_at == $t) | .subject_ids | length
')

echo "Next review: ${NEXT_REVIEW_AT} (${REVIEW_COUNT} items)"

# ─── 2. Exchange refresh token for a short-lived access token ────────────────

echo "Getting Google access token..."

ACCESS_TOKEN=$(curl -sf \
  -X POST \
  -d "client_id=${GCAL_CLIENT_ID}&client_secret=${GCAL_CLIENT_SECRET}&refresh_token=${GCAL_REFRESH_TOKEN}&grant_type=refresh_token" \
  "https://oauth2.googleapis.com/token" \
  | jq -r '.access_token')

DEBUG=$(curl -s \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://www.googleapis.com/calendar/v3/calendars/primary")
echo "Calendar debug: ${DEBUG}"
  
# ─── 3. Upsert the Calendar event ────────────────────────────────────────────
# PUT with a fixed event ID = stateless create-or-replace, zero duplicates.

FIXED_EVENT_ID="wkninextreviewauto"

PLURAL=""
[ "$REVIEW_COUNT" -ne 1 ] && PLURAL="s"
EVENT_TITLE="🦀 WaniKani — ${REVIEW_COUNT} review${PLURAL} ready"

# URL-encode the calendar ID for use in the endpoint path
CAL_ID_ENCODED=$(jq -rn --arg v "$GCAL_CALENDAR_ID" '$v | @uri')

EVENT_BODY=$(jq -n \
  --arg id    "$FIXED_EVENT_ID" \
  --arg title "$EVENT_TITLE" \
  --arg time  "$NEXT_REVIEW_AT" \
  '{
    id: $id,
    summary: $title,
    description: "Auto-synced by wanikani-review-notifier.\nhttps://www.wanikani.com/review",
    start: { dateTime: $time, timeZone: "UTC" },
    end:   { dateTime: $time, timeZone: "UTC" },
    reminders: {
      useDefault: false,
      overrides: [{ method: "popup", minutes: 0 }]
    },
    colorId: "5"
  }')

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$EVENT_BODY" \
  "https://www.googleapis.com/calendar/v3/calendars/${CAL_ID_ENCODED}/events/${FIXED_EVENT_ID}")

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "Done. Event upserted (HTTP ${HTTP_STATUS}): '${EVENT_TITLE}' at ${NEXT_REVIEW_AT}"
else
  echo "Calendar API error: HTTP ${HTTP_STATUS}"
  exit 1
fi
