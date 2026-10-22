# Testing the Dev Build v0 app on your iPhone
Status: guide (DV-04 first slice)
Last Updated: 2026-10-22

First-slice scope: Settings + connection check, capture (1080p, 120 fps if supported), upload → analyze →
real shot metrics + LaneSight Score, session feedback. Dev-user auth (no Apple/Google sign-in yet). Full
24-screen design, Supabase persistence of shots, and OAuth come next.

## 1. Start the Mac API
```
cd ~/Documents/LaneSight/lanesight-core
lanesight_api/serve.sh --memory        # first test: in-memory, no Supabase auth users needed
```
(Drop `--memory` later to write to the real Supabase project — that needs a real signed-in user.)

## 2. Expose it to your phone over Tailscale (once)
```
tailscale serve --bg --https=443 http://127.0.0.1:8787
tailscale serve status                 # confirm
caffeinate -s                          # keep the Mac awake while you bowl
```
Your tailnet URL is **https://shaynes-macbook-pro.tail7fa640.ts.net** (both devices are already on the tailnet).

## 3. Build + run the app on your iPhone
```
cd ~/Documents/LaneSight/ios/LaneSight
xcodegen generate                      # if the .xcodeproj isn't present
open LaneSight.xcodeproj
```
In Xcode: select the **LaneSight** target → **Signing & Capabilities** → set **Team** to your Apple
developer account (bundle id `com.lanesight.app`). Plug in your iPhone, pick it as the run destination,
press **Run** (⌘R). First run: on the phone, Settings → General → VPN & Device Management → trust your
developer cert. (Device Mode is already enabled on this Mac via `DevToolsSecurity`.)

## 4. In the app
- **Settings** → API URL = `https://shaynes-macbook-pro.tail7fa640.ts.net`, dev user = any id (e.g. `shayne`).
  Tap **Check connection** — you should see the API versions and `mode: memory`.
- **Capture** → point at the lane, Record, take your shot, Stop. The clip uploads, the job runs on the Mac
  (~20–40 s), and the **Result** screen shows the measured metrics + your LaneSight Score (it'll say
  "Building" until there are enough shots and Power ranges are set — that's expected and honest).

## Troubleshooting
- "Check connection" fails → is `serve.sh` running, and did `tailscale serve` succeed? Try the URL in the
  phone's browser (`/health`).
- Analysis fails on a clip → the metrics come back with a reason; capture is never blocked (DEC-045). A
  clean down-lane framing with the lane and foul line in view works best.
