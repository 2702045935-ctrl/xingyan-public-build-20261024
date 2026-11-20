# Device stress matrix

These fixtures are local-only and are enabled exclusively through launch
environment variables. They never write synthetic data to the backend or the
normal chat cache.

## Profiles

| Profile | Generated data |
|---|---|
| `chats-4000` | 4,000 mixed direct/group conversation rows |
| `chats-10000` | 10,000 mixed conversation rows |
| `chats-100000` | 100,000 mixed conversation rows |
| `messages-1000` | 1,000 messages across 20 groups, first group auto-opens |
| `messages-10000` | 10,000 messages across 20 groups |
| `messages-100000` | 100,000 messages; first group owns 75%, 19 groups share the rest |
| `messages-300000` | 300,000 messages in one default group for the extended history stress run |
| `moments-10000` | 10,000 Moments cards |
| `moments-100000` | 100,000 Moments cards |
| `full-100000` | 100k conversations, 100k messages and 100k Moments |

## Optional controls

| Variable | Meaning |
|---|---|
| `XINGYAN_CHAT_STRESS` | Alias for a conversation-list count |
| `XINGYAN_MESSAGE_STRESS` | Alias for a total message count |
| `XINGYAN_MOMENT_STRESS` | Alias for a Moments count |
| `XINGYAN_STRESS_GROUPS` | Message stress group count, default 20, maximum 500 |
| `XINGYAN_STRESS_MEMBERS` | Members in each synthetic group, default 1,000, maximum 5,000 |
| `XINGYAN_STRESS_AUTO_OPEN` | `1` opens the first message-stress group automatically |

Every message-stress group uses the same message mix: text, long text, mentions,
quotes, recalled messages, files and transfers. The group-info API is also
served locally so ChatInfo and the full-member list can be tested without
network data.

The synthetic stress cap is 300,000. The chat UI keeps a bounded active window
and still consumes exactly one prefetched page at a time.
