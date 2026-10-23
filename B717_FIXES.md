# B717 targeted fixes

Baseline: `4052bef` (the source used by the working B717 package).

Do not merge the later full iOS branch. The later endpoint, certificate,
group-call, and audio-pipeline changes are excluded because they make the
working B717 build unable to connect.

## Included

- Clearing a chat invalidates the server cursor, local cache, current chat
  memory, pagination, hidden IDs, and the chat-list preview immediately.
- Bulk clear uses the same path without resetting navigation for every chat.
- Real-time message events update the chat-list preview from the event payload.
- Group history search includes the Huawei-style `群成员` and `日期` entries.
- Search covers the Huawei category set and opens the matching message.
- Video calls enable TRTC automatic resolution adjustment and cloud QoS
  (smooth-first), while retaining B717's existing audio weak-network handling.
- Automatic bottom pinning is suppressed for 0.45 seconds while the user is
  dragging or the list is decelerating, preventing group chats from jumping.
- Focusing the composer forces two bottom scroll passes after the keyboard
  changes height, so the newest message stays visible.
- Call mute/speaker buttons update their visual state and haptics before the
  audio route/TRTC work runs on the next main-loop turn.
- Groups without an uploaded avatar render a member-photo mosaic, with the
  green group fallback when fewer than two portraits are available.
- Wi-Fi/cellular interface changes trigger an endpoint probe and realtime
  reconnect; a failed probe rotates to the next configured endpoint.
- The message long-press menu uses viewport coordinates and re-samples the
  bubble frame after layout, including call-record bubbles.

## Protected baseline

- `Sources/ChatDeferred.swift` is unchanged.
- `Sources/ContactsView.swift` is unchanged.
- `Sources/ChatDetailView.swift` changes are limited to clear/search event
  handling; chat protection and message rendering logic are not removed.

## Device acceptance

- [ ] B717 baseline still connects after installing the rebuilt package.
- [ ] Clearing one chat removes its list preview and reopened history.
- [ ] Clearing all chats removes every preview and does not reset navigation
      once per chat.
- [ ] Group search shows `群成员` and `日期`; member filter returns only that
      member's matching messages; selecting a result opens the original message.
- [ ] One-to-one and group voice still work.
- [ ] Mute/speaker buttons change immediately during voice calls.
- [ ] Video call negotiates and weak-network QoS parameters are accepted.
- [ ] Wi-Fi/cellular switching reconnects without restarting the app.
- [ ] New groups without an uploaded avatar show a member mosaic.
- [ ] Composer focus returns to the newest message after the keyboard opens.
- [ ] Long-press action cards are anchored to the pressed bubble.
- [ ] Fast scrolling in a long group chat does not jump to an unrelated place.
- [ ] Huawei build and data are unchanged.
