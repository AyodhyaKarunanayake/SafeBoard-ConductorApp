# Passenger app: "Text conductor" with replies

Status on 2026-09-22, applied to the newest passenger copy
`ResearchApp\SafeBoard_28745_FinalProject\05_Source_Code\safeboard`
(the other copies on the Desktop are older and were not touched).

## Applied

1. **New file** `lib/services/conductor_message_service.dart`
   - `send(...)` writes the message to a new `conductor_messages` collection
     (fire-and-forget, `try/catch`, same convention as the app's other services).
   - `watchMyMessages(...)` streams this passenger's messages with the
     conductor's replies (empty stream when offline, never throws).
2. **`lib/screens/journey/journey_screen.dart`**
   - the "Text the conductor" sheet now actually sends the tapped preset,
     and shows "Your messages" with the conductor's replies, live;
   - `_showConductorMessageSheet` takes the seat allocation; its call site
     passes `ticket.allocation`;
   - the sheet scrolls (`isScrollControlled` + `SingleChildScrollView`) so the
     conversation cannot overflow a small screen;
   - a private `_ConductorReplyWatcher` widget was added to the file.

The snackbar "Sent to conductor: ..." and everything else in the flow is
unchanged. A backup of the original is next to the file:
`journey_screen.dart.bak-before-conductor-messages` (delete the service file and
restore the backup to undo everything).

## NOT applied yet: one insertion

`_ConductorReplyWatcher` (which shows "Conductor replied: ..." as a snackbar while
the Journey screen is open) exists but is not placed on the screen, so it is
currently unused (an analyzer "unused element" warning, no effect on the app).
Without it, replies still show inside the sheet; with it, the passenger is also
told when one arrives. To finish, in `build()` of `journey_screen.dart` add it as
the first child of the `Stack`:

```dart
return Scaffold(
  body: Stack(
    children: [
      // Shows a snackbar when the conductor replies to a text message.
      _ConductorReplyWatcher(
        key: ValueKey('reply-watcher-${alloc.journeyId}'),
        passengerId: authProvider.passenger?.passengerId ?? 'p_28745',
        journeyId: alloc.journeyId,
      ),
      Column(
        children: [
          _buildHeader(bus, route, occupancyFraction, occupancyColor, occupancyLabel),
          // ... unchanged
```

## Also applied (2026-09-22): ending a journey frees the seat in Firestore

Previously `TicketsProvider.endJourney` only flipped local flags, so nothing told
Firestore (or the conductor app) that a seat was free again.

- **New file** `lib/services/seat_release_service.dart`: `release(allocationId)`
  does `update({'status': 'released'})` on `seat_allocations/{id}` (fire-and-forget,
  `try/catch`, never `set()`, so it can only mark an allocation that already exists).
  `'released'` is the status the schema already defines for a freed seat.
- **`lib/providers/tickets_provider.dart`** `endJourney`: releases every seat on the
  ticket (a group ticket ends for the whole group). Both the manual "Yes, I've
  arrived" button and the automatic end after the alighting stop go through this
  one method, so both are covered. Backup: `tickets_provider.dart.bak-before-seat-release`.

Nothing else in the passenger flow changes. Limitation: the passenger app does not
listen to `seat_allocations`, so if the conductor moves a standing passenger to a
seat, that passenger's own ticket screen still shows their old place.

## Document shape

`conductor_messages/{msg_<millis>}`:

| field | value |
|---|---|
| `message_id` | `msg_<millis>` (also the document id) |
| `journey_id` | the allocation's journey, e.g. `JRN_87_001` |
| `bus_id` | the allocation's bus |
| `passenger_id` | the signed-in passenger's id |
| `seat_number` | e.g. `4B` |
| `message_text` | the preset text |
| `sent_datetime` | ISO-8601 string |
| `status` | `sent` -> `read` -> `replied` (set by the conductor app) |
| `replies` | array of `{text, sent_datetime, conductor_id}`, added by the conductor app |

## SOS needs no change

The SOS button already files an `incident_reports` document (`SOS_<millis>`,
status `escalated`); the conductor app raises the pop-up from it.
