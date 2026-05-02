# WaniKani Calendar Sync 🦀

> This project is largely inspired by [sergioparamo/wanikani-review-notifier](https://github.com/sergioparamo/wanikani-review-notifier) — all credit for the original idea goes to him.

A simple, fast, and dependency-free way to sync your next WaniKani review session directly into Google Calendar — which can trigger notifications the moment reviews unlock.

This project is intentionally minimal. It uses **zero external dependencies** and no separate hosting service. It runs entirely within **GitHub Actions** using a single **Bash script**.

This architecture is 100% free by combining the generous free tiers of GitHub Actions and Google Calendar API.

## 🚀 The Stack

- **Scheduler:** GitHub Actions (running every 8 minutes)
- **Runner:** GitHub Actions (Standard Ubuntu runner) — 2000 minutes/month on the free tier
- **Logic:** A single `wanikani_calendar_sync.sh` Bash script
- **Tools:** `curl` and `jq` (pre-installed on the runner)
- **Calendar:** Google Calendar API (free, via OAuth 2.0)

## 💡 How It Works

1. **Schedule:** The `.github/workflows/wanikani-calendar-sync.yml` workflow wakes up **every 8 minutes** and takes around 10–15 seconds to finish.
2. **Checkout:** The workflow checks out your repository's code.
3. **Execute:** It runs `wanikani_calendar_sync.sh`, passing in your API keys as environment variables.
4. **Script logic:**
   - Calls the WaniKani `/summary` API endpoint using `curl`.
   - Parses the JSON response using `jq` to get the next review time and item count.
   - Exchanges your OAuth refresh token for a short-lived Google access token.
   - Upserts a single Google Calendar event at the next review time using a fixed event ID — so re-runs silently overwrite the same event, no duplicates ever.
5. **On your phone:** The event triggers a popup notification exactly when your reviews unlock.

## 🛠️ Setup Guide

### Step 1: Fork the Repository

Click the "Fork" button at the top of this page to copy this project to your own GitHub account. The workflow files are already included.

### Step 2: Get Your WaniKani API Token

1. Go to your WaniKani account settings.
2. **API Tokens** → [Generate a new Personal Access Token (V2)](https://www.wanikani.com/settings/personal_access_tokens).
3. No specific permissions required beyond the default read access.
4. Save this token. This is your `WANIKANI_API_TOKEN`.

### Step 3: Set Up Google Cloud

#### 3.1 Create a project

1. Go to [console.cloud.google.com](https://console.cloud.google.com).
2. Click the project dropdown (top left) → **New Project** → give it any name → **Create**.

#### 3.2 Enable the Google Calendar API

1. With your project selected, go to **APIs & Services → Library**.
2. Search for "Google Calendar API" → click it → **Enable**.

#### 3.3 Configure the OAuth consent screen

1. Go to **APIs & Services → OAuth consent screen**.
2. User type: **External** → **Create**.
3. Fill in the mandatory fields: app name (anything), your Gmail as support email, and your Gmail again as developer contact.
4. Click through **Scopes** and **Test users** without changes — just **Save and Continue** on each.
5. On the **Test users** step, add your own Gmail address.

#### 3.4 Create OAuth credentials

1. Go to **APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID**.
2. Application type: **Desktop app** → name it anything → **Create**.
3. Note your **Client ID** and **Client Secret**.
4. Go back into the client → **Edit** → add `http://localhost` to **Authorised redirect URIs** → **Save**.

#### 3.5 Get your refresh token

Run the following in your terminal to generate an authorization URL:

```sh
CLIENT_ID="your-client-id.apps.googleusercontent.com"

echo "https://accounts.google.com/o/oauth2/v2/auth?\
client_id=${CLIENT_ID}\
&redirect_uri=http://localhost\
&response_type=code\
&scope=https://www.googleapis.com/auth/calendar.events\
&access_type=offline\
&prompt=consent"
```

Open the URL in your browser, authorize the app, and copy the `code` parameter from the redirect URL (the part after `?code=` and before `&`).

Then exchange it for a refresh token:

```sh
curl -X POST "https://oauth2.googleapis.com/token" \
  --data-urlencode "code=YOUR_AUTH_CODE" \
  --data-urlencode "client_id=YOUR_CLIENT_ID" \
  --data-urlencode "client_secret=YOUR_CLIENT_SECRET" \
  --data-urlencode "redirect_uri=http://localhost" \
  --data-urlencode "grant_type=authorization_code"
```

Save the `refresh_token` value from the response. This is your `GCAL_REFRESH_TOKEN`.

### Step 4: Create a Dedicated Google Calendar (optional but recommended)

Keeping WaniKani reviews on their own calendar lets you show/hide them in one click.

1. In Google Calendar, click **+** next to "Other calendars" → **Create new calendar** → name it (e.g. "WaniKani") → **Create**.
2. Open the calendar's settings → **Integrate calendar** → copy the **Calendar ID** (a long string ending in `@group.calendar.google.com`).
3. Use that as your `GCAL_CALENDAR_ID` secret. For your primary calendar, use your Gmail address directly.

### Step 5: Add GitHub Secrets

Go to your repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Name | Value |
| --- | --- |
| `WANIKANI_API_TOKEN` | Your WaniKani Personal Access Token |
| `GCAL_CLIENT_ID` | OAuth 2.0 Client ID from Google Cloud |
| `GCAL_CLIENT_SECRET` | OAuth 2.0 Client Secret from Google Cloud |
| `GCAL_REFRESH_TOKEN` | The refresh token from step 3.5 |
| `GCAL_CALENDAR_ID` | Target calendar ID (primary Gmail address or `@group.calendar.google.com` ID) |

## ⚠️ Things to Keep in Mind

- **GitHub Actions scheduled workflows** can be delayed by a few minutes during peak times — this is normal and expected, hence the run every 8 minutes. This also allow to update review times when doing lessons.
- **Refresh token expiry:** Publish your OAuth consent screen to increase the lifespan of Google refresh tokens from **7 days to 6 months of inactivity**. Go to Google Cloud → APIs & Services → OAuth consent screen → Publish App. Since it's a personal app with no sensitive scopes beyond calendar.events, Google won't require a formal review. Once published, refresh tokens last 6 months of inactivity instead of 7 days. If the workflow suddenly stops working after a long break, repeat step 3.5 and update the `GCAL_REFRESH_TOKEN` secret.
- **Calendar event ID charset**: Google Calendar event IDs only allow lowercase letters a–v and digits 0–9 (base32hex). Letters w, x, y, and z are not valid and will cause a 400 error! Keep this in mind if you ever change the fixed event ID in the script.
