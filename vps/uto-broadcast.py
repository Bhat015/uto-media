#!/usr/bin/env python3
"""Create the next YouTube Live broadcast for the 24/7 loop (YouTube Data API v3).

YouTube does not create a new broadcast on its own after one ends, so before every
11 h 50 m session the stream script runs `uto-broadcast.py new`, which:
  1. removes leftover *upcoming* loop broadcasts,
  2. creates a new public broadcast with auto-start / auto-stop,
  3. binds it to the stream whose key is $YT_STREAM_KEY,
  4. sets its category to Education.

One-time setup (as root):  python3 uto-broadcast.py auth
  Asks for the OAuth client ID/secret (Google Cloud, type "TVs and Limited Input devices"),
  shows a code to approve at google.com/device, and saves /etc/uto/yt-oauth.json.
Standard library only.
"""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error, datetime

CRED = "/etc/uto/yt-oauth.json"
SCOPE = "https://www.googleapis.com/auth/youtube"
API = "https://www.googleapis.com/youtube/v3"
TITLE = "Under the Ordinary: 24/7 Everyday Science Explainers (Replays)"
DESC = ("Replays of our explainer videos, running around the clock: how everyday things really work, "
        "explained simply with original 2D animation.\n\n"
        "These are replays, not live commentary. Every video in this stream is also on the channel, "
        "where you can watch it from the start.\n\n"
        "New explainers go up every day. Subscribe to Under the Ordinary for the hidden technology "
        "behind everyday things.")
CATEGORY = "27"  # Education


def post_form(url, data):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return json.loads(e.read() or b"{}")


def api(method, path, token, params=None, body=None):
    url = f"{API}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"YouTube API {method} {path} failed: {e.code} {e.read()[:400]!r}")


def auth():
    os.makedirs(os.path.dirname(CRED), exist_ok=True)
    cid = input("OAuth client ID: ").strip()
    secret = input("OAuth client secret: ").strip()
    d = post_form("https://oauth2.googleapis.com/device/code", {"client_id": cid, "scope": SCOPE})
    if "device_code" not in d:
        raise SystemExit(f"Could not start sign-in: {d}")
    print(f"\nOn your phone or computer open {d['verification_url']} and enter: {d['user_code']}")
    print("Sign in with the Google account that owns the Under the Ordinary channel, then allow access.\n")
    interval = int(d.get("interval", 5))
    while True:
        time.sleep(interval)
        t = post_form("https://oauth2.googleapis.com/token", {
            "client_id": cid, "client_secret": secret, "device_code": d["device_code"],
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"})
        if "refresh_token" in t:
            break
        if t.get("error") == "slow_down":
            interval += 5
        elif t.get("error") != "authorization_pending":
            raise SystemExit(f"Sign-in failed: {t}")
    with open(CRED, "w") as f:
        json.dump({"client_id": cid, "client_secret": secret, "refresh_token": t["refresh_token"]}, f)
    os.chmod(CRED, 0o640)
    try:
        import grp
        os.chown(CRED, 0, grp.getgrnam("uto").gr_gid)
    except Exception:
        pass
    print("Saved. Testing...")
    token = access_token()
    ch = api("GET", "channels", token, {"part": "snippet", "mine": "true"})
    print("Connected to channel:", ch["items"][0]["snippet"]["title"] if ch.get("items") else "?")


def access_token():
    c = json.load(open(CRED))
    t = post_form("https://oauth2.googleapis.com/token", {
        "client_id": c["client_id"], "client_secret": c["client_secret"],
        "refresh_token": c["refresh_token"], "grant_type": "refresh_token"})
    if "access_token" not in t:
        raise SystemExit(f"Token refresh failed: {t}")
    return t["access_token"]


def new():
    key = os.environ.get("YT_STREAM_KEY", "")
    if not os.path.exists(CRED):
        raise SystemExit("not set up: run 'sudo python3 uto-broadcast.py auth' once")
    token = access_token()
    # the stream (ingestion point) that uses our key
    streams = api("GET", "liveStreams", token, {"part": "id,cdn", "mine": "true", "maxResults": 50})
    sid = next((s["id"] for s in streams.get("items", [])
                if s.get("cdn", {}).get("ingestionInfo", {}).get("streamName") == key), None)
    if not sid:
        raise SystemExit("no YouTube live stream uses this stream key")
    # clear leftover upcoming loop broadcasts so they don't pile up
    up = api("GET", "liveBroadcasts", token, {"part": "id,snippet", "broadcastStatus": "upcoming", "maxResults": 50})
    for b in up.get("items", []):
        if b["snippet"]["title"] == TITLE:
            api("DELETE", "liveBroadcasts", token, {"id": b["id"]})
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    b = api("POST", "liveBroadcasts", token, {"part": "snippet,status,contentDetails"}, {
        "snippet": {"title": TITLE, "description": DESC, "scheduledStartTime": now},
        "status": {"privacyStatus": "public", "selfDeclaredMadeForKids": False},
        "contentDetails": {"enableAutoStart": True, "enableAutoStop": True, "enableDvr": True,
                           "latencyPreference": "normal", "monitorStream": {"enableMonitorStream": False}}})
    api("POST", "liveBroadcasts/bind", token, {"id": b["id"], "part": "id,contentDetails", "streamId": sid})
    try:
        api("PUT", "videos", token, {"part": "snippet"},
            {"id": b["id"], "snippet": {"title": TITLE, "description": DESC, "categoryId": CATEGORY}})
    except SystemExit as e:
        print("category not set:", e)
    print(f"broadcast ready: https://www.youtube.com/watch?v={b['id']}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "auth":
        auth()
    elif cmd == "new":
        new()
    else:
        print(__doc__)
