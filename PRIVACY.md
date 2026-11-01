# Privacy policy

Last updated: 1 November 2026

Sielto is made by Edvig Smirnov, who is responsible for the data described here. Questions and requests: sieltoapp@gmail.com

## The short version

Everything you enter stays on your device unless you choose otherwise. Sielto has no account, no email, no phone number, no ads, no analytics and no telemetry. It reaches the network only for the features below, and only once you turn them on. With Settings → Fully offline on, it reaches nothing at all.

## On your device

Your Spaces, entries, categories and settings live in a database on your device, encrypted with SQLCipher. Its key stays in your system's secure storage, or behind your passphrase on Linux without a keyring. A random user id is made on the device when you first start the app. It names no one.

## Cloud Spaces

A Space you set to Cloud syncs through Supabase, a hosted database in the EU (Frankfurt, Germany). Local Spaces never leave the device. For cloud Spaces the server holds:

- the random user id, and a sign-in for each of your linked devices
- each device's name (the phone model or the computer's name) and when it last synced
- the name you chose to show to the people you share a Space with
- the Space's title, settings, categories, schedules, entries and notes
- the names and roles you give other members, which only you see
- your IP address, which Supabase records in its own short-lived service logs, and which the app records for one day after a wrong device or invite code, to slow down guessing

The server can read these rows: they are encrypted on Supabase's disks and on the way there, but not with your own key. Everyone you share a Space with sees its contents and your shown name.

Payments and incomes dated more than 30 days in the past are deleted from the server every night. Your devices keep them. The server waits while a member of the Space has been away for 20 to 90 days, so that member doesn't lose entries they haven't synced yet.

## Linking devices

A device link code is stored only as a hash and expires after 5 minutes. Your Recovery Key passes from one device to the other encrypted for the receiving device, so the server never sees it.

## Google Drive backups

Only if you connect Google Drive. Sielto then saves a daily backup into a hidden app folder in your own Drive, which other apps can't see. Each backup is encrypted with your Recovery Key before it leaves the device, so Google can't read it. Sielto keeps your Google email on the device to show which account is connected. Google's privacy policy applies to your Google account.

## Holidays

Holidays for 204 countries are built into the app. For years beyond the built-in ones, the app asks date.nager.at for the public holidays of your chosen country, once you allow it. The request names the country and the year, and the service sees your IP address.

## Update checks

Only if you turn them on. Once a day the app asks GitHub for the latest release, and GitHub sees your IP address. Updates download from GitHub too.

## Deleting your data

- An entry or a category you delete stays on the server marked as deleted, so your other devices learn of it. Entries then go with the 30-day rule above, and everything goes with its Space.
- Delete Space removes a cloud Space and everything in it from the server, for every member.
- Settings → Your devices → Unlink removes a device and its sign-in from the server.
- Settings → Security → Delete everything from the cloud removes your cloud Spaces, memberships, shown name and every device's sign-in from the server. This device keeps your Spaces as local ones.
- Uninstalling the app removes everything on that device. Drive backups stay in your Drive until you remove them, or disconnect Sielto in your Google account settings.

## Your rights

Under the GDPR you can ask to see, correct, export or delete your data, and you can complain to your data protection authority. Most of this you can do in the app: your data is on your device, Backup exports it, and the steps above delete it. Since there is no account, a request about server data has to include your user id, which the app shows under Settings → About Sielto.

## Processors

- Supabase, Inc. hosts the cloud database in the EU.
- Google LLC stores Drive backups, encrypted, in your own Drive.
- Neither receives anything while you use only local Spaces.

## Changes

A change to this policy ships with an app update and is listed in the release notes.
