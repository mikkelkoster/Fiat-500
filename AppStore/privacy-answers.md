# App Store Connect → App Privacy

**Answer: "No, we do not collect data from this app."** The label then reads *Data Not Collected*.

Why that's accurate under Apple's definition ("collect" = transmitted off the device in a way
that you or a third-party partner can access beyond what's needed to serve the request):

| Data | Where it goes | Collected? |
|---|---|---|
| Brand account email, password, PIN | Keychain on the iPhone; sent only to the car brand's sign-in and API servers, which the owner already uses, to perform their request | No |
| Car status, position, trips | Read from the brand's servers; shown and kept on the device | No |
| iPhone location | Used on the device for distance and directions; never sent | No |
| Car position for the weather | Sent to Apple Weather (WeatherKit) to look up the temperature; Apple's service, the developer never receives it | No |
| Notifications, schedules, settings | On the device | No |
| Analytics, crash reporting, ads, tracking | None in the app | No |

There are no third-party SDKs. TestFlight/App Store crash reports are Apple's and don't change
the answer. Tracking: **No**.

If Apple pushes back, the fallback is to declare *Contact Info → Email* and *Identifiers → User ID*
as collected, "linked to the user", purpose *App Functionality*, not used for tracking.
