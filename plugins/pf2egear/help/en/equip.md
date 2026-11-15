---
toc: Pathfinder Second Edition
summary: Managing Gear and Inventory
aliases:
- invest
- uninvest
- equip
- unequip
---

# Equipping And Investing Items

In order for weapons, armor, shields, and magic items to be useful, they must be equipped, invested, or both, depending on what they are. Weapons, armor, and shields can be equipped; weapons, armor, magic items, and bags with the _invested_ trait can be invested, such as a voyager's pack with `invest bags/0`.

Equipping and investing an item both take effect immediately. Your daily preparations invest the same items again each day, so an item stays invested until you `uninvest` it.

A few things to be aware of: 
* You cannot equip or invest an item that is in a bag. The item must be in your main inventory.
* Most characters can only invest ten items on any given day. The feat Incredible Investiture expands this to 12. 
* Once you invest an item, the code will assume you want to invest that item daily, and will continue to invest that item at daily prep unless you `uninvest` it. This is because most people will invest the same items daily most of the time, changing what is invested only occasionally or for a specific purpose. 

## Commands

`gear/equip <category> = <item number>`: Equips the specified item in `<category>`. (Alias: `equip`)
`gear/unequip <category> = <item number>`: Unequips the specified item in `<category>`. (Alias: `unequip`)

`gear/invest <category> = <item number>`: Invests the item numbered `<item number>` in `<category>`, now and at each day's preparations. List several items separated by spaces to invest them all at once. (Alias: `invest`)
%t **Note:** Some magic items, such as handwraps of mighty blows, are in the weapons or armor category.
%t **Note:** In an encounter that's already running, a newly invested item takes effect the next time the GM rests you (see `help rest`).
`gear/invest <category> = <item number>/<choice>`: Invests an item that requires a choice when you invest it, such as a Charm of Resistance's damage type or an Entertainer's Cincture's skill, with the choice you specify (`<choice>`). If you leave out the choice, the game lists the choices and doesn't invest the item. `item/view` shows the choice you made. (Alias: `invest`)
%t **Note:** To change your choice, `uninvest` the item, then invest it again with the new choice.
%t **Note:** Some items require more than one choice. Specify them in order, separated by slashes, such as `invest magicitem/0/athletics/Kamin` for a crown of intellect's skill and language.

### Apex items
An invested apex item raises one of your attribute modifiers by 1, or to +4, whichever is higher. Your sheet marks the raised attribute `(apex)`, and `item/view` shows which attribute an apex item raises.
%t **Note:** You can have only one apex item invested at a time. To swap, `uninvest` the one you have, then invest the other. The new one counts after the GM next rests you (see `help rest`).
%t **Note:** An apex item that raises Intelligence requires a skill and a language the first time you invest it. You're trained in that skill while the item counts. `item/view` shows the skill and language. The language isn't added to your sheet's language list.
`gear/uninvest <category> = <item number>`: Uninvests the item numbered `<item number>` in `<category>`, now and at each day's preparations. (Alias: `uninvest`)