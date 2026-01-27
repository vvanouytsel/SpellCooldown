# SpellCooldown

A simple World of Warcraft addon that displays a visual indicator when you use an ability that's on cooldown.

## What It Does

When you press a spell or ability that's currently on cooldown, SpellCooldown shows you a large, customizable icon with the remaining cooldown time displayed right on your screen. This makes it easy to see exactly how long you need to wait before you can use that ability again.

The display appears briefly when you try to use a cooldown ability, then disappears automatically, keeping your screen uncluttered.
Due to Blizzard's restrictions added to the combat API in Midnight, this addon only works when out of combat.

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

