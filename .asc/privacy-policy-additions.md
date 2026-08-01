# Privacy policy — gaps vs. the App Privacy answers

Checked live copy at https://sticks-golf.app/privacy (200, "Last updated: July 2026").
It covers account info, golf activity, location, and SMS phone numbers. It is missing
four things that the App Privacy answers — and the App Store description — now assert.

## Must add

1. **Apple Health / HealthKit.** Not mentioned anywhere. Guideline 5.1.3 requires apps
   that use HealthKit to have a privacy policy describing health data use, and to state
   it is never used for advertising, marketing, or data mining. This is a standalone
   rejection reason, separate from the 2.5.1 note.
2. **Push notification tokens.** `push_tokens` stores the APNs device token keyed to
   `user_id`. That is the "Identifiers → Device ID" box; the policy names no identifier.
3. **Background location.** The policy says location is used "while you use the on-course
   GPS." The app collects location with the screen locked, and `POST /matches/:id/tee`
   persists tee coordinates on the server. Both need saying out loud.
4. **Profile photo.** "avatar" appears once, as an optional profile detail. The App
   Privacy answer declares "User Content → Photos or Videos," so the policy should say a
   photo is uploaded and stored.

## Should fix

- **Phone number scope.** Framed as SMS-only. Phone is also used for friend discovery
  (`setPhone` in Settings) so people can find you.
- **Account deletion.** Policy says email us. The app deletes in Settings (`DELETE /me`),
  and the App Store description promises exactly that. Make them match.
- **Service providers.** Esri/ArcGIS serves the satellite tiles. No account data goes to
  them, but tile requests reveal the map area being viewed.

---

# Ready-to-paste text — all of it goes on https://sticks-golf.app/privacy

One URL is all Apple needs. No second page, no separate health page. Placement against the
live page, top to bottom:

- Keep the intro paragraph as-is.
- **Replace** the four bullets under "Information we collect" with the block below.
- **Insert** the new "Apple Health" section immediately after "How we use information"
  (before "SMS / text messaging").
- Keep "SMS / text messaging" as-is.
- **Append** the service-providers sentence to the end of the existing "Sharing" section.
- Keep "Data retention & security" as-is.
- **Insert** "Deleting your account" after "Your choices", before "Contact".
- Keep "Contact" as-is. Bump "Last updated" to the date you publish.

## Information we collect

**Account information** you provide — username, email address, display name, and optional
profile details (GHIN number, goal handicap). If you add a profile photo, the image is
uploaded to our servers and stored with your account until you replace or remove it.

**Golf activity** you create in the app — rounds, hole scores, courses, groups,
tournaments, and side-game results.

**Location.** With your permission, Sticks uses your device's precise location to show
distances to the green and hazards, to find nearby courses, and to keep your round, Live
Activity, and Apple Watch yardages current. Because a round is played with the phone in
your pocket, location updates continue while the app is in the background or the screen is
locked, for as long as a round is active; iOS shows the blue location indicator the whole
time. Most of this stays on your device — the coordinates we store are the tee locations
you fix for a round. Location is never sold and is never used for advertising.

**Phone number** — optional. Used so friends can find and follow you by number, and, if
you opt in separately, to send you the text updates described below.

**Device identifiers** — if you turn on notifications, we store the Apple push token for
that device with your account so we can deliver round alerts. You can remove it by turning
notifications off or deleting your account.

## Apple Health

If you allow it, Sticks records your round on Apple Watch as a Golf workout. While the
workout is running, Sticks reads your heart rate, active energy, and walking distance from
Apple Health to show them during the round, and writes the finished workout back to Health
so the round counts toward your rings and appears in the Health app.

This data is processed on your device and inside Apple Health. **We never transmit,
store, or receive your health data on our servers, and we never use it for advertising,
marketing, data mining, or share it with any third party.** Health access is optional —
Sticks asks before each round unless you choose to remember your answer, and you can
decline or revoke access at any time in the Health app under Sources, or in iOS Settings →
Privacy & Security → Health. Declining does not limit scoring or GPS.

## Deleting your account

You can permanently delete your account and everything in it at any time: open Sticks →
Settings → Delete account. This removes your profile, rounds, scores, groups, photo, phone
number, and any stored push tokens. You can also email support@sticks-golf.app and we will
do it for you.

## Service providers (add to the existing Sharing section)

Satellite hole imagery is served by Esri/ArcGIS. Those requests reveal only the map area
being viewed — no account information is sent with them.
