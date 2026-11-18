---
toc: Community
summary: Scheduling game events.
aliases:
- waitlist
- death_consent
- event_limit
- event_consent
---
# Events Commands

The events system is an in-game calendar that lets you schedule events.

> Learn how the events system works in the [Events Tutorial](/help/events_tutorial).

## Viewing Events

`events`  - Lists upcoming events
`event <#>` - Views an event

## Creating and Deleting Events

**Note:** When creating and editing events, times must be specified in the **server's** timezone.  This will be automatically converted to local time for anyone who has their timezone set.

`event/create <title>=<month> <day>, <year> <time>/<description>` - Creates an event with an optional event description. The default format is `February 15, 2019 6:54pm`
`event/edit <#>` - Grabs the current event into your edit buffer (see `help edit`)
`event/update <#>=<title>/<date and time>/<description>`
`event/delete <#>`
`event/scene <#>` - Creates a scene for the event and invites everyone who signed up to join it. Note: The scene will be PUBLIC, in a temp room, and the event participants will still get the choice whether to join or decline the invitation."

## Signing Up For Events

`event/signup <#>=<comment>` - Sign up for an event.  If already signed up, this command can be used to change your comment.
`event/cancel <#>` - Removes your signup.
`event/cancel <#>=<name>` - Removes someone's signup (organizers only)

When an event has a player limit and every spot is taken, `event/signup` adds you to the event's waitlist instead. If someone cancels, the first person on the waitlist moves onto the roster and gets a notice. `events` marks an event you're waiting for with `[W]`.

## Player Limits and Death Consent

These commands are for the event's organizer and for staff.

`event/limit <#>=<number>`: Sets the maximum number of players for an event (`<#>`). People who sign up after the event is full join the waitlist.
%t **Note:** If you lower the limit, the most recent sign-ups move to the waitlist. If you raise it, the people at the top of the waitlist move onto the roster. Everyone who moves gets a notice.
`event/limit <#>=none`: Removes an event's player limit, which moves everyone on the waitlist onto the roster.
`event/consent <#>=on`: Marks an event as death consent, which means characters in it can die. Everyone already signed up or waiting gets a notice, along with the command to withdraw.
`event/consent <#>=off`: Removes an event's death-consent mark.

`events` shows `[DC]` next to a death-consent event, and `event <#>` shows the player count, the roster with each character's level and class, and the waitlist. On the web portal, the create and edit event pages include both settings.

