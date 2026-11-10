# Windbar Privacy Policy

Last updated: 9 November 2026

Windbar is a macOS menu bar app for controlling Dreo smart fans. This policy explains what it does
with your information. The short version: Windbar collects nothing, and the developer never receives
any of your data.

## What Windbar collects

**Nothing.** There is no analytics, no crash reporting, no telemetry, no advertising identifier, and
no account with the developer. No data about you or your usage is ever sent to us, because there is
no "us" to send it to: there is no Windbar server.

## What Windbar stores on your Mac

| Data | Where it is kept | Why |
|---|---|---|
| Your Dreo email and password | macOS Keychain | To sign in to Dreo's service on your behalf |
| Your Dreo access token | macOS Keychain | To stay signed in between launches |
| Your fan list and last-used fan | App preferences on your Mac | To draw the menu and support the global hotkey |
| Your chosen keyboard shortcuts | App preferences on your Mac | To trigger fans from the keyboard |

All of it stays on your Mac, in Windbar's own preferences and its own Keychain items. Deleting the
app does not remove them automatically: delete its preferences file, and remove its Keychain
entries with Keychain Access.

## What is sent to Dreo

Windbar is a client for Dreo's own service, so using it necessarily means talking to Dreo:

- **Signing in.** Your email address and a hash of your password go to Dreo's authentication
  endpoint over HTTPS. Windbar never sends your password anywhere else.
- **Controlling a fan.** Commands (power, speed, oscillation, mode) travel to Dreo's servers over an
  encrypted WebSocket, and Dreo relays them to the fan. Even when the fan is in the same room, the
  round trip goes through Dreo. That is how the hardware works and Windbar cannot change it.
- **Checking for updates.** Windbar asks GitHub for the release feed
  (`releases/latest/download/appcast.xml` in this repository) to learn whether a newer version
  exists. Nothing about you or your fans is included in that request beyond what any web request
  carries, such as your IP address.
- **Setting up a new fan.** Your WiFi network name and password are sent directly to the fan over
  Bluetooth, not over the internet, and are not stored by Windbar afterwards.

Dreo's handling of that information is governed by **Dreo's own privacy policy**, not this one.
Windbar is an independent project and has no relationship with Dreo.

## Bluetooth

Windbar uses Bluetooth only to find and configure a new Dreo fan during pairing. It does not scan
for, track, or record any other device.

## Children

Windbar is a utility for controlling fans and is not directed at children. It collects no personal
information from anyone.

## Changes

Any future change to this policy will be committed to this repository, so its history is public and
auditable.

## Contact

Questions or concerns: open an issue at
<https://github.com/lucid-fabrics/windbar/issues>.
