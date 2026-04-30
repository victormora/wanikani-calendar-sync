#!/bin/sh
# wanikani_calendar_sync.sh
# Fetches the next WaniKani review time and upserts a single Google Calendar event.
# Uses a fixed event ID so re-runs silently overwrite — no duplicates ever.
#
# Required env vars:
#   WANIKANI_API_TOKEN   — your WaniKani v2 API token
#   GCAL_CLIENT_ID       — OAuth2 client ID (Desktop app type)
#   GCAL_CLIENT_SECRET   — OAuth2 client secret
#   GCAL_REFRESH_TOKEN   — long-lived refresh token
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

# Count items in the next review bucket — compare raw timestamp before normalising
REVIEW_COUNT=$(echo "$SUMMARY" | jq --arg t "$NEXT_REVIEW_AT" '
  .data.reviews[] | select(.available_at == $t) | .subject_ids | length
')

# Default to 0 if no matching bucket found
REVIEW_COUNT=${REVIEW_COUNT:-0}

# Normalise timestamp — strip microseconds so Google Calendar accepts it
NEXT_REVIEW_AT=$(echo "$NEXT_REVIEW_AT" | sed 's/\.[0-9]*Z$/Z/')

# End time = start + 1 hour (required for notification to persist on mobile)
EVENT_END=$(date -u -d "${NEXT_REVIEW_AT} + 1 hour" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
  || date -u -v+1H -jf "%Y-%m-%dT%H:%M:%SZ" "${NEXT_REVIEW_AT}" "+%Y-%m-%dT%H:%M:%SZ")

echo "Next review: ${NEXT_REVIEW_AT} (${REVIEW_COUNT} items)"

# ─── 2. Exchange refresh token for a short-lived access token ────────────────

echo "Getting Google access token..."

ACCESS_TOKEN=$(curl -sf \
  -X POST \
  -d "client_id=${GCAL_CLIENT_ID}&client_secret=${GCAL_CLIENT_SECRET}&refresh_token=${GCAL_REFRESH_TOKEN}&grant_type=refresh_token" \
  "https://oauth2.googleapis.com/token" \
#!/bin/sh
# wanikani_calendar_sync.sh
# Fetches the next WaniKani review time and upserts a single Google Calendar event.
# Uses a fixed event ID so re-runs silently overwrite — no duplicates ever.
#
# If reviews are overdue, the event slides forward snapping to the nearest :00
# or :30, firing a fresh notification every 30 minutes until reviews are done.
#
# Required env vars:
#   WANIKANI_API_TOKEN   — your WaniKani v2 API token
#   GCAL_CLIENT_ID       — OAuth2 client ID (Desktop app type)
#   GCAL_CLIENT_SECRET   — OAuth2 client secret
#   GCAL_REFRESH_TOKEN   — long-lived refresh token
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

# Count items in the next review bucket — compare raw timestamp before normalising
REVIEW_COUNT=$(echo "$SUMMARY" | jq --arg t "$NEXT_REVIEW_AT" '
  .data.reviews[] | select(.available_at == $t) | .subject_ids | length
')

# Default to 0 if no matching bucket found
REVIEW_COUNT=${REVIEW_COUNT:-0}

# Normalise timestamp — strip microseconds so Google Calendar accepts it
NEXT_REVIEW_AT=$(echo "$NEXT_REVIEW_AT" | sed 's/\.[0-9]*Z$/Z/')

# ─── 2. Sliding window — snap to nearest :00 or :30 if reviews are overdue ───

NOW_EPOCH=$(date -u "+%s")
REVIEW_EPOCH=$(date -u -d "${NEXT_REVIEW_AT}" "+%s" 2>/dev/null \
  || date -u -jf "%Y-%m-%dT%H:%M:%SZ" "${NEXT_REVIEW_AT}" "+%s")

if [ "$REVIEW_EPOCH" -lt "$NOW_EPOCH" ]; then
  echo "Reviews overdue — sliding window to nearest :00 or :30..."

  # Current minute
  NOW_MINUTE=$(date -u "+%M")

  if [ "$NOW_MINUTE" -lt 30 ]; then
    # Snap back to :00 of current hour
    NEXT_REVIEW_AT=$(date -u "+%Y-%m-%dT%H:00:00Z")
  else
    # Snap back to :30 of current hour
    NEXT_REVIEW_AT=$(date -u "+%Y-%m-%dT%H:30:00Z")
  fi
fi

# End time = start + 1 hour
EVENT_END=$(date -u -d "${NEXT_REVIEW_AT} + 1 hour" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
  || date -u -v+1H -jf "%Y-%m-%dT%H:%M:%SZ" "${NEXT_REVIEW_AT}" "+%Y-%m-%dT%H:%M:%SZ")

echo "Next review: ${NEXT_REVIEW_AT} (${REVIEW_COUNT} items)"

# ─── 3. Exchange refresh token for a short-lived access token ────────────────

echo "Getting Google access token..."

ACCESS_TOKEN=$(curl -sf \
  -X POST \
  -d "client_id=${GCAL_CLIENT_ID}&client_secret=${GCAL_CLIENT_SECRET}&refresh_token=${GCAL_REFRESH_TOKEN}&grant_type=refresh_token" \
  "https://oauth2.googleapis.com/token" \
  | jq -r '.access_token')

# ─── 4. Upsert the Calendar event ────────────────────────────────────────────
# Google Calendar event IDs must be base32hex: only a-v and 0-9.
# Upsert = POST to create, PUT to update if it already exists.

FIXED_EVENT_ID="vvanikanirevievvauto" # No w-z allowed!

PLURAL=""
[ "$REVIEW_COUNT" -ne 1 ] && PLURAL="s"
EVENT_TITLE="🦀 WaniKani — ${REVIEW_COUNT} review${PLURAL} ready"

# URL-encode the calendar ID for use in the endpoint path
CAL_ID_ENCODED=$(jq -rn --arg v "$GCAL_CALENDAR_ID" '$v | @uri')

EVENT_BODY=$(jq -n \
  --arg id    "$FIXED_EVENT_ID" \
  --arg title "$EVENT_TITLE" \
  --arg time  "$NEXT_REVIEW_AT" \
  --arg end   "$EVENT_END" \
  '{
    id: $id,
    summary: $title,
    description: "Auto-synced by wanikani-review-notifier.\nhttps://www.wanikani.com/review",
    start: { dateTime: $time, timeZone: "UTC" },
    end:   { dateTime: $end,  timeZone: "UTC" },
    reminders: {
      useDefault: true
    },
    colorId: "5"
  }')

# Try PUT (update) first — falls back to POST (create) on 404
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$EVENT_BODY" \
  "https://www.googleapis.com/calendar/v3/calendars/${CAL_ID_ENCODED}/events/${FIXED_EVENT_ID}")

if [ "$HTTP_STATUS" = "404" ]; then
  echo "Event not found, creating..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$EVENT_BODY" \
    "https://www.googleapis.com/calendar/v3/calendars/${CAL_ID_ENCODED}/events")
fi

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "Done. Event upserted (HTTP ${HTTP_STATUS}): '${EVENT_TITLE}' at ${NEXT_REVIEW_AT}"
else
  echo "Calendar API error: HTTP ${HTTP_STATUS}"
  exit 1
fi

