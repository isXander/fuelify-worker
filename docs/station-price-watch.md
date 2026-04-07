# Station Price Watch

Watch specific fuel stations and receive push notifications when their price changes.

## Overview

Users register once, link their device for push notifications, then add station watches. The worker checks for price changes at the end of every hourly ingestion sync. If a watched station's latest price differs from the price last notified about, a silent data push is sent via Firebase Cloud Messaging (FCM). The app receives the data payload and is responsible for presenting the notification.

There is no authentication. The `user_id` returned at registration is the sole identity — persist it on-device (Keychain / UserDefaults). If lost, the user must re-register.

---

## Firebase Setup

### 1. Create a Firebase project

Create a project in the [Firebase Console](https://console.firebase.google.com/). No Google Analytics or other services are needed — only Cloud Messaging.

### 2. Add an iOS app

Register the app's bundle ID. Download the `GoogleService-Info.plist` and add it to the Xcode project.

### 3. Generate a service account key

Go to **Project Settings > Service accounts > Generate new private key**. This downloads a JSON file. The worker needs three fields from it: `project_id`, `client_email`, and `private_key`.

Store the entire JSON as a Cloudflare Worker secret:

```bash
npx wrangler secret put FCM_SERVICE_ACCOUNT
# paste the full JSON contents
```

### 4. iOS app integration

Add the `firebase-ios-sdk` package (`FirebaseMessaging` product only). On launch:

```swift
FirebaseApp.configure()
Messaging.messaging().delegate = self

// Request notification permission
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
    guard granted else { return }
    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
}
```

When the FCM token arrives or refreshes, register it with the worker:

```swift
func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken, let userId = persistedUserId else { return }
    // POST /devices/register { "user_id": userId, "device_token": token }
}
```

---

## API Endpoints

Base URL: `https://fuelify.isxander.dev`

All request bodies are JSON. All responses are JSON. Errors return `{ "success": false, "message": "..." }`.

### POST /users/register

Create a new user identity. Call once on first launch, persist the returned `user_id`. No request body required.

**Response (200):**
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

### POST /devices/register

Link an FCM device token to a user. Call on every FCM token refresh. If the token already exists, it is re-associated with the given user.

**Request:**
```json
{
  "user_id": "550e8400-...",
  "device_token": "dGhpcyBpcyBhIGZha2UgdG9rZW4..."
}
```

**Response:** `200` empty body.

### POST /watch/station

Start watching a station. The current price is recorded internally so the user is not immediately notified about a price they already see — notifications only fire on subsequent changes.

**Request:**
```json
{
  "user_id": "550e8400-...",
  "station_id": "abc123",
  "fuel_type": "E10"
}
```

`fuel_type` is per-watch — a user can watch the same station for different fuel types, or different stations for different fuel types. One of: `E10`, `E5`, `B7Standard`, `B7Premium`, `B10`, `HVO`.

**Response:** `200` empty body. Silently succeeds if the watch already exists.

### DELETE /watch/station

Stop watching a station for a specific fuel type.

**Request:**
```json
{
  "user_id": "550e8400-...",
  "station_id": "abc123",
  "fuel_type": "E10"
}
```

**Response:** `200` empty body. Silently succeeds if the watch didn't exist.

### GET /watches?user_id=...

List all stations the user is currently watching.

**Response (200):**
```json
{
  "stations": [
    {
      "station_id": "abc123",
      "trading_name": "Tesco Extra",
      "brand_name": "Tesco",
      "fuel_type": "E10"
    }
  ]
}
```

---

## Push Notification Payload

Notifications are **silent data-only pushes** — there is no `notification` block, so iOS will not display anything automatically. The app must handle the data in `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` or a `NotificationServiceExtension` and present a local notification.

**FCM data payload:**
```json
{
  "type": "price_change",
  "station_id": "abc123",
  "station_name": "Tesco Extra",
  "fuel_type": "E10",
  "old_price": "134.5",
  "new_price": "131.9"
}
```

All values are strings (FCM requirement). Prices are in **pence per litre** with one decimal place (e.g. `"131.9"` = 131.9p/L).

The app is responsible for:
- Formatting the notification text
- Grouping multiple price changes if several arrive at once
- Deciding whether to show a notification at all (e.g. skip if the price went up and the user only cares about drops)

---

## App-Side Lifecycle

Recommended integration flow:

```
First launch:
  1. POST /users/register  -->  persist user_id
  2. Request notification permission
  3. POST /devices/register { user_id, device_token }

On FCM token refresh:
  4. POST /devices/register { user_id, new_device_token }

User taps "Watch" on a station (with a fuel type selected):
  5. POST /watch/station { user_id, station_id, fuel_type }

User taps "Unwatch":
  6. DELETE /watch/station { user_id, station_id, fuel_type }

Loading watch list screen:
  7. GET /watches?user_id=...

On receiving a data push:
  8. Parse the data payload
  9. Present a local notification (UNMutableNotificationContent)
```

If the user reinstalls the app and the persisted `user_id` is lost, call `/users/register` again. The old user record becomes orphaned — the stale device token will be cleaned up automatically when FCM returns `UNREGISTERED`.

---

## How It Works on the Backend

### Timing

The worker runs an hourly cron ingestion that fetches all fuel price data from the GOV.UK Fuel Finder API. The upstream API's incremental mode is only date-precise (`yyyy-mm-dd`), so every hourly sync re-fetches **all prices for the current day**. Most of this data is unchanged — the existing upsert uses a `WHERE price != EXCLUDED.price` guard to skip no-op writes.

### Change detection

After all fuel price batches are ingested (`conclude_sync`), the worker runs a single query across the `watched_stations` table. Each watch row stores a `last_notified_price` — the price the user was last told about. The query joins this against the current latest price in `fuel_prices` and returns only rows where the two differ.

This means:
- No per-batch overhead during ingestion — change detection is a single query at the end
- Only watched stations are scanned, not all ~8,000 stations
- Re-running the same sync (identical data) produces zero notifications because `last_notified_price` already matches

After notifications are sent, each watch row's `last_notified_price` is updated so the same change is never re-notified.

### FCM auth

The worker mints an RS256 JWT from the Firebase service account key, exchanges it for a Google OAuth2 access token, and caches that token in Cloudflare KV with a 55-minute TTL (tokens expire after 60 minutes). Subsequent syncs within the hour reuse the cached token — no JWT signing or token exchange needed.

### Stale token cleanup

If FCM returns `UNREGISTERED` or `NOT_FOUND` for a device token (user uninstalled, token rotated without re-registration), the worker deletes that `devices` row. No manual cleanup is needed.

### Failure handling

If the notification check or any FCM call fails, the error is logged but the sync still completes successfully. The `last_notified_price` is only updated after a successful send, so a failed notification will be retried on the next sync cycle.

---

## D1 Usage Estimates

The Cloudflare Workers paid plan includes **5M rows read / month** and **100K rows written / month** on D1.

### Notification check query (runs once per sync, 24 syncs/day)

The query reads ~4 rows per entry in `watched_stations` (the watch row itself + station + fuel_prices index scan + fuel_prices row).

| Watched stations (N) | Rows/query | Rows/month (720 syncs) | vs 5M free tier |
|---|---|---|---|
| 100                   | 400        | 288K                   | Well within     |
| 500                   | 2,000      | 1.4M                   | Within          |
| 2,000                 | 8,000      | 5.8M                   | $0.001/mo extra |
| 8,000                 | 32,000     | 23.0M                  | $0.018/mo extra |
| 16,000                | 64,000     | 46.1M                  | $0.041/mo extra |

"Watched stations" is the total number of (user, station, fuel_type) watch triples. A user watching 3 stations for E10 = 3 entries.

D1 read overage costs $0.001 per million rows, so even at 16K watches the notification query adds ~$0.04/month.

### Writes

- **Per notification sent:** 1 UPDATE to `watched_stations` (update `last_notified_price`)
- **Stale token cleanup:** 1 DELETE per unregistered device
- **User API calls:** 1 INSERT/UPDATE per registration or watch action

Writes are user-driven and proportional to actual price changes. Typical volume is well under 100K/month at moderate scale.

### What the feature does NOT add

- No extra reads during ingestion batches — the fuel price upserts are unchanged
- No extra writes during ingestion — `last_notified_price` is only written when a notification is sent
- No new Cloudflare Queues or KV namespaces
