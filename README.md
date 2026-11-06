# SpellCooldown

A simple World of Warcraft addon that displays a visual indicator when you use an ability that's on cooldown.

## What It Does

When you press a spell or ability that's currently on cooldown, SpellCooldown shows you a large, customizable icon with the remaining cooldown time displayed right on your screen. This makes it easy to see exactly how long you need to wait before you can use that ability again.

The display appears briefly when you try to use a cooldown ability, then disappears automatically, keeping your screen uncluttered.

## Supported Clients

| Client | Combat support |
| --- | --- |
| Retail (Midnight 12.0.5+) | In and out of combat |
| WoW Forever (1.60.1) | In and out of combat |
| TBC Classic Anniversary (2.5.5) | In and out of combat |

WoW Forever is built on the Retail game code, combat restrictions included, so it uses the same display path as Retail described below.

### A note on Midnight's combat restrictions

Midnight put the player's own cooldown numbers behind "secret values": an addon may hold them but may not do arithmetic or comparisons on them, which is why earlier versions of this addon switched themselves off in combat.

Blizzard's rule is that addons may still *display* combat information, they just may not compute with it — and displaying is all this addon ever wanted to do. On Retail the countdown is rendered by a `Cooldown` widget: the addon hands it an opaque duration object and the widget draws the number itself. Nothing secret is ever read, compared, or formatted locally, which is what makes it legal in combat. The widget's swipe, edge and bling are switched off, so all it contributes is the text.

This same path is used in and out of combat, so the display looks and ticks identically either way. Classic clients, which have no duration APIs and no restrictions, keep the original locally-computed countdown.

The decision about *whether* a spell is on cooldown uses only the fields Blizzard flags as never-secret, so it stays legal either way.

### Requires "Show Numbers for Cooldowns"

Blizzard gates *all* cooldown countdown text behind the `countdownForCooldowns` CVar — the **Show Numbers for Cooldowns** checkbox under Options → ActionBars. An addon can suppress the numbers on its own frame but cannot force them on, so with that setting off the timer cannot be drawn at all in combat. The addon detects this and says so at login, and out of combat it falls back to formatting the readable values itself.

Other consequences worth knowing:

- The client owns the formatting on Retail, so the countdown matches your action bars: whole seconds, switching to minutes above a minute. **Show Decimal Seconds** is applied through the widget's millisecond threshold, and font size and colour through a Font object handed to the widget.
- Item cooldowns are read directly and then wrapped in a duration object so they render through the same path. Items are not part of the automation surface Blizzard restricts, so this normally works; if that ever changes the addon skips the item rather than erroring.

## Features

- **Visual Cooldown Display**: Shows the icon of the ability you just used along with the exact time remaining
- **Fully Customizable**: Adjust size, colors, borders, fonts, and display duration to match your UI
- **Positioned Anywhere**: Drag the frame to any location on your screen
- **Clean Interface**: Only appears when needed, automatically hides when the cooldown ends
- **Live Preview**: See changes in real-time as you adjust settings

## Configuration

Access the settings through the Game Menu:
1. Press **ESC**
2. Go to **Options** → **AddOns** → **SpellCooldown**

### Available Settings

- **Icon Size**: Customize the width and height of the cooldown icon
- **Font Size**: Adjust how large the countdown text appears
- **Display Duration**: Control how long the icon stays on screen (or keep it visible until the cooldown ends)
- **Text Color**: Choose any color for the countdown timer
- **Border**: Enable/disable borders and customize their size and color
- **Frame Position**: Unlock the frame to drag it anywhere on your screen, then lock it in place
- **Debug Mode**: Enable detailed logging to troubleshoot spell detection

