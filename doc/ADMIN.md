### Setting up KOReader

1. In KOReader, open **Tools → Progress sync → Custom sync server**.
2. Enter `https://__DOMAIN____PATH__` (no trailing slash).
3. Use **Register / Login** to create an account. The account is specific to this server. It is not your YunoHost account.

### Registration

Registration is set at install time. You can change it any time in the app's **Configuration** panel in the webadmin. Once you have created your accounts, turn registration off so strangers can't use your server.

### Access

The server is an API for KOReader, not a website, so it has no tile in the user portal. It must stay reachable by **visitors**, because KOReader logs in with its own sync credentials, not YunoHost SSO.

### Technical notes

- No containers are used. The package builds OpenResty and the Lua `gin` framework from source on your server during install and every upgrade. These steps take a few minutes.
- Data lives in a dedicated Redis instance (service `__APP__-redis`) that listens only on localhost. Its data is in `__DATA_DIR__/redis` and is included in YunoHost backups.
- Logs are in `/var/log/__APP__/`.
