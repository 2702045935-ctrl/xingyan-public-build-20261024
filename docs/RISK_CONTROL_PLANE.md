# Risk control-plane ownership

Risk state is account state. It must follow the user's owner shard and must
never be treated as whichever shard happened to serve an admin request.

## Rules

- `users.json`, `risk.json`, `risk-events.jsonl`, and `violations.json` for a
  user are read and written on that user's owner shard.
- `risk-whitelist.json` is also read from the owner shard. A whitelist entry
  disables automatic risk scoring and media blocking for that username only.
- Admin lists aggregate risk and violation rows from every configured shard.
- Handling a violation locates the shard that contains the violation ID and
  writes the handled state back to that same file.
- A missing risk file on a non-owner shard must never fall back to the local
  shard's `risk.json`; it is an empty scoped store until the owner is resolved.

## Release gate

- `node --check server/server.js`
- `python tools/verify-risk-shard-routing.py`
- `node --test server/test/favorites-sync.test.js`
- `node --test server/test/moment-delete-persistence.test.js`
- A two-cell drill must prove that a violation recorded on cell B is visible in
  the admin control plane and can be handled without restarting a shard.

Do not replace these rules with a global risk off switch. User-specific
whitelisting or handling the exact violation is the safe, auditable recovery
path.
