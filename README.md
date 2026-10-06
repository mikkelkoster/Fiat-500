# 500e Preheat

A small iOS app that preheats (or cools) a Fiat 500e (registration **ED35079**) from your phone, by Siri, and on a schedule.

It talks to the same Stellantis Uconnect cloud service as the official Fiat app, so the car needs an active Uconnect Services subscription and you need your Fiat account email, password and 4-digit Uconnect PIN.

## What it does

- **Preheat / Stop:** one large button. It sends the car's `ROPRECOND` / `ROPRECOND_OFF` command and waits for the car to confirm.
- **Status:** battery %, range and whether the cable is plugged in. Pull down to refresh.
- **Schedules:** set a "warm by" time (e.g. 07:30), the days, and how many minutes before to start.
- **Siri & Shortcuts:** "Preheat my car with 500e Preheat", plus *Preheat Car* and *Stop Preheating Car* actions in Shortcuts.

## How scheduling works (and its limits)

iOS does not let an app run code at an exact time, so each schedule is covered in two ways:

1. **A notification** at the start time. If the app is open it preheats straight away. Otherwise, long-press the notification and tap **Preheat now**. That runs in the background without opening the app.
2. **Background refresh** requested just before the start time. When iOS grants it in time, the app preheats on its own. iOS decides when that happens, so it is not guaranteed.

**For a fully automatic, on-time schedule, use a Shortcuts automation.** This is the one approach iOS guarantees:

1. Shortcuts › Automation › **+** › **Time of Day**
2. Set the time (e.g. 07:10) and the days, then choose **Run Immediately**
3. Add the action **Preheat Car** (from 500e Preheat)

If you use Shortcuts automations, turn off the matching in-app schedule so you don't get a notification as well.

## Build & run

Requirements: a Mac with Xcode 15 or later, an iPhone with iOS 17 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen            # generates FiatPreheat.xcodeproj from project.yml
open FiatPreheat.xcodeproj
```

In Xcode, choose your team under *Signing & Capabilities*. Change the bundle ID if `dk.koster.FiatPreheat` is taken. Then run it on your iPhone. A free Apple ID works, but the app expires after 7 days. A paid developer account (or TestFlight) avoids that.

On first launch, enter your Fiat account and PIN. The app finds the car on your account and shows its VIN. The plate defaults to ED35079 and can be changed in Settings.

Run the unit tests with ⌘U. They cover AWS request signing (against AWS's reference vector), schedule maths and status parsing.

## Test signing in from a Mac (no phone needed)

`fiat-cli` runs the app's own Uconnect code in Terminal, so you can check the login and the car
connection before installing anything:

```sh
swift run fiat-cli vehicles   # sign in, list the cars on the account
swift run fiat-cli status     # battery, range, plug
swift run fiat-cli preheat    # start climate and wait for the car to confirm
swift run fiat-cli stop
```

It asks for your email, password and PIN (hidden as you type), or reads `FIAT_EMAIL`,
`FIAT_PASSWORD` and `FIAT_PIN`. Nothing is stored. Errors print what Fiat's server answered.

## How it talks to the car

```
Gigya login (loginmyuconnect.fiat.com)
  → Gigya JWT
  → Cognito identity token (authz.sdpr-01.fcagcv.com)
  → temporary AWS credentials (cognito-identity.eu-west-1)
  → SigV4-signed calls to channels.sdpr-01.fcagcv.com
      GET  /v4/accounts/{uid}/vehicles
      GET  /v3/accounts/{uid}/vehicles/{vin}/status/
      POST /v1/accounts/{uid}/vehicles/{vin}/remote   {command, pinAuth}
  (pinAuth comes from POST mfa.fcl-01.fcagcv.com/v1/accounts/{uid}/ignite/pin/authenticate)
```

The endpoints and public client keys come from the open-source [py-uconnect](https://github.com/hass-uconnect/py-uconnect) project (used by the Home Assistant Uconnect integration). This is **not an official API**. Stellantis can change it without notice, and if they do, the app will stop working until the values in `FiatPreheat/Uconnect/UconnectConfig.swift` are updated. Use it at your own risk.

Your credentials are stored only in the iPhone Keychain (this device only) and are sent only to Fiat/Stellantis servers.

## Design

The app uses Torque's design system (`torque-ios`): the same tokens (`Ink`, `Type`, `Space`,
`Radius`, `Elevation`), Geist, and the same components (Card, CardSection, PrimaryButton,
SmallButton, DayPicker, NumberStepper, DayTag, SheetHeader, Toast). They are ported into
`FiatPreheat/Design/`. When a token changes in Torque, copy it across so the two apps stay alike.

## Project layout

```
project.yml                     XcodeGen spec
FiatPreheat/
  App/          app entry, shared CarModel state
  Uconnect/     UconnectClient (login, status, commands), SigV4 signer, config
  Scheduling/   PreheatSchedule, ScheduleCoordinator (notifications + background refresh)
  Intents/      App Intents for Siri & Shortcuts
  Views/        SwiftUI screens
  Design/       Tokens and components ported from Torque
  Resources/    Geist font files
  Support/      Keychain storage
FiatPreheatTests/
```
