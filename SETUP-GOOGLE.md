# Connecting Google Classroom

Locker can pull classes and assignments straight from Google Classroom. This is
optional — everything in the app works without it.

Locker only ever **reads**. It cannot turn work in, post, or change anything in
Classroom.

Google requires every app that talks to Classroom to have its own credentials,
so there's a one-time setup. It's free and takes about five minutes.

## 1. Make a Google Cloud project

1. Go to <https://console.cloud.google.com/projectcreate>.
2. Name it anything (`Locker` works). Create it, and make sure it's selected.

## 2. Turn on the Classroom API

1. Go to <https://console.cloud.google.com/apis/library/classroom.googleapis.com>.
2. Click **Enable**.

## 3. Set up the consent screen

1. Go to **APIs & Services → OAuth consent screen**.
2. Choose **External**, then **Create**.
3. Fill in an app name and your own email where required. Save and continue.
4. On the **Scopes** step, just continue — Locker requests its scopes at sign-in.
5. On **Test users**, click **Add users** and add **the Google account used for
   school**. This step matters: without it, sign-in is rejected.
6. Save.

You do not need to publish the app or go through verification. A project in
testing mode works indefinitely for the accounts you list as test users.

## 4. Create the credentials

1. Go to **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. Application type: **Desktop app**. Name it anything. Create.
3. Copy the **Client ID** and **Client secret**.

## 5. Connect in Locker

1. Open Locker → **Settings → Sync**.
2. Paste the Client ID and Client secret.
3. Click **Connect**. A browser window opens; sign in with the school account
   and approve the read-only access.
4. The browser says you can close the tab, and Locker starts syncing.

## What syncing does

- New Classroom assignments show up in Locker automatically.
- Turning something in on Classroom checks it off in Locker.
- Notes, priority, time estimates, and reminder settings are **never**
  overwritten by a sync — those are yours.
- If an assignment is deleted in Classroom, Locker keeps it and marks it
  "removed upstream" rather than deleting your copy.
- A class you already made by hand gets linked to the matching Classroom course
  instead of being duplicated. Renaming a class in Locker sticks.

## If it doesn't work

**"Access blocked" or "app is blocked"** — some school districts turn off
third-party app access for student accounts. That's a setting only the school's
Google Workspace admin can change. Nothing else in Locker is affected; keep
adding work manually.

**"Sign-in was cancelled"** — the browser window was closed, or it timed out
after five minutes. Try again.

**Sign-in loops or fails right away** — double-check that the school account is
listed under **Test users** on the consent screen, and that the credential type
is **Desktop app**.

**It worked before and stopped** — Google expires tokens for projects in testing
mode after a week of disuse. Click **Connect** again in Settings.
