# Notes for App Review

Paste into App Store Connect → App Review Information → Notes. Leave "Sign-in required"
**off**: the sample car needs no account, and a real account would give control of a real car.

---

Luft works with cars connected to the car maker's remote services, using the account the
owner already has in the brand's own app. A reviewer will not have such a car, so the app
includes a complete sample car:

1. Open the app. On the first screen, tap **Try with a sample car** (below Get started).
2. Every screen and control then works on pretend data, with nothing sent anywhere:
   start the climate (and stop it), swipe between battery and range, pull down to refresh,
   lock and unlock with the slider, Flash lights, Find (map), Boot, Schedule (add, edit, delete),
   Settings, Trips and Alerts.
3. Settings → **Leave sample car** returns to the first screen.

Luft has no servers. The owner's login is stored in the iPhone's keychain and sent only to
the car brand's own servers to sign in. Location is used on the device to show the distance
to the car and is not sent anywhere.

Luft is an independent app and is not affiliated with any car maker; the welcome screen
says so.
