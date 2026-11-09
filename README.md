# Forget-Me-Not(e) Forever
A Reminder and To-do list Addon for WoW Forever

(WoW Forever, interface 16001)

Reminds you to learn new spell ranks and train professions at the right time.

## Install
Unzip so the folder sits at `World of Warcraft\_forever_\Interface\AddOns\ForgetMeNot\` (the `.toc` must be directly inside it). Restart the game or `/reload`.

## First run
Talk to your class trainer once. The addon reads every spell, rank, level and cost straight from the trainer window, so nothing is guessed. After that it knows what unlocks at every level. Talk to profession trainers once too, so it records where they stand.

## What it does
- Level up / login: chat message plus on-screen alert listing spells you can learn now and the total cost.
- Trainer window: a "Learn all" box next to it, with a confirmation before it spends gold.
- Professions (Vanilla rules): tells you when you can train Journeyman (skill 50), Expert (skill 125) or Artisan (skill 200); level requirements are read from the profession trainer, when you're capped and when you're close to the cap. Cooking, First Aid and Fishing note that higher ranks come from a book or a quest.
- Any capital city (Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity), or within 40 yards of a trainer you need: a to-do list with a Waypoint button for each trainer.
- Unspent talent points: reminder after level-up and in the panel.
- New profession recipes: talk to a profession trainer once; it tells you when your skill is high enough for new recipes there.
- Capped profession (e.g. 75/75): shows in the to-do list when you enter a capital or get close to the trainer. Optional: a warning on every craft or gather (off by default, in Options).
- Recipes waiting: the panel lists every recipe you have the skill for but haven't bought, with prices; ones you can't afford are shown in red. "What can I learn?" window (spells + recipes) opens anywhere: button in the panel, Shift-click the minimap button, or /fmn recipes.
- Class quests for all nine classes (from Forever quest guides): abilities like stances, forms, demons and racial priest spells, plus key weapon quests. Skip one with /fmn skip <quest name>.
- Minimap button: left-click opens the panel, right-click opens the to-do list, drag to move.

## Commands
`/fmn` panel · `/fmn alts` · `/fmn forget <name>` · `/fmn check` · `/fmn list` · `/fmn options` · `/fmn skip <spell>` · `/fmn unskip <spell>` · `/fmn reset`

## Please test and tell me
1. Does the trainer box show up next to the trainer window, with the right spells and cost?
2. Does "Learn all" learn everything, or stop after one? (If it stops, I'll change it to one click per spell.)
3. Do profession messages match what the trainer offers?
4. If anything goes wrong, install BugSack + BugGrabber and send me the error text.
