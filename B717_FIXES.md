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
- [ ] Video call negotiates and weak-network QoS parameters are accepted.
- [ ] Huawei build and data are unchanged.
