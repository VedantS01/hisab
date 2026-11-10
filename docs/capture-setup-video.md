# Capture setup video — script

Target: one unlisted YouTube video, under 3 minutes, portrait screen
recording of an iPhone (Control Centre › Screen Recording, mic on). Chapters
match the setup screen's steps so a viewer can jump. Once uploaded, build
with `--dart-define=HISAB_SETUP_VIDEO=https://youtu.be/<id>` and the setup
screen shows **Watch the setup video**.

Before recording: Hisab installed, capture **on**, no existing Hisab
automations, a clean Shortcuts library page, Do Not Disturb on.

| # | Time | Screen | Say |
|---|---|---|---|
| 0 | 0:00 | Hisab › Settings › Capture setup | "Hisab can file your bank SMS and emails for you. iPhone apps can't read messages, so we'll give Shortcuts one job: hand each alert to Hisab. Three minutes." |
| 1 | 0:15 | Shortcuts › + › Add Action › search "Hisab" › Add Transaction Alert | "First, a share shortcut. Add Hisab's Add Transaction Alert action…" |
| 1 | 0:30 | Tap Alert Text › Shortcut Input; rename to **Log to Hisab**; ⓘ › Show in Share Sheet | "…set its text to Shortcut Input, name it exactly *Log to Hisab*, and show it in the share sheet." |
| 1 | 0:50 | Back in Hisab › Test your setup › Share shortcut › **Run** | "Hisab can test it: it runs your shortcut with a ₹1 sample and shows what came back. Amount, payee, date and time, all ticked. Nothing is saved." |
| 2 | 1:05 | Shortcuts › Automation › + › Message › Message Contains **Rs**, Sender empty | "Now the automatic part. A Message automation, containing *Rs*. Leave Sender empty; bank IDs like HDFCBK can't be contacts." |
| 2 | 1:25 | Run Immediately, Notify off › Add Transaction Alert › Alert Text = Shortcut Input | "Run immediately, and the same one action." |
| 2 | 1:40 | Duplicate for **INR** | "Make a second one for *INR*. Between them they catch nearly every bank." |
| 2 | 1:55 | Hisab › SMS automation › **Send** › send to own number › back to Hisab | "Test it: Hisab opens Messages with the sample. Send it to yourself and come back. Green ticks mean it works." |
| 3 | 2:15 | Settings › Apps › Mail › add Gmail; Fetch every 15 min; Automation › Email › Sender = bank address | "Optional: bank emails. Add Gmail to Apple Mail, then an Email automation for your bank's address, same action." |
| — | 2:45 | Hisab › Transactions › Detections with a real alert | "That's it. Each alert lands here with its time, ready to categorise." |

Recording notes
- Blur or avoid real account numbers; the sample alert uses XX0000 and a
  test VPA.
- iOS wording differs slightly between versions (Run Immediately vs
  "Run without asking"); say the meaning, not the exact label.
- Re-record step 2 if iOS shows the "Notify when run" banner over the result.
