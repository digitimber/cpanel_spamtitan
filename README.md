# SpamTitan cPanel Integration Hook

A bash hook script that integrates SpamTitan's REST API (v3) with cPanel's standardized hooks system. Automatically manages SpamTitan domains, policies, authentication, and domain administrator accounts in response to cPanel account lifecycle events.

## What it does

- **Account creation** -- adds the domain to SpamTitan, configures quarantine policy, sets up IMAP authentication, creates a `stadmin@domain.com` mailbox, and provisions it as a Domain Administrator in SpamTitan
- **Account removal** -- checks whether DNS is being retained (transfer/rebuild) or deleted (permanent removal). If permanent, removes the domain from SpamTitan. If DNS is retained, preserves all SpamTitan settings so the customer's allow/block lists, quarantine preferences, and admin access survive the migration
- **Domain park/unpark** -- adds or removes alias/addon domains from SpamTitan
- **MX routing changes** -- adds the domain to SpamTitan when MX is set to local, removes it when set to remote

## Features

- External config file (keeps tokens out of the script)
- Timestamped logging with severity levels to `/var/log/spamtitan_hook.log`
- HTTP response checking on all API calls with configurable retry logic
- Graceful handling of domains that already exist in SpamTitan (preserves settings on transfer/rebuild)
- Automatic provisioning of a SpamTitan Domain Administrator mailbox on new accounts

## Requirements

- cPanel/WHM (tested on v126 and v134)
- SpamTitan with REST API v3 enabled (tested on v8.01.07)
- `jq` installed on the cPanel server
- `curl` installed on the cPanel server

## Files

- `SpamTitanDomainsv2.sh` -- the hook script
- `spamtitan.conf` -- configuration file

## Installation

1. Create the directory and copy files:

```
mkdir -p /var/cpanel/spamtitan
cp SpamTitanDomainsv2.sh /var/cpanel/spamtitan/
cp spamtitan.conf /var/cpanel/spamtitan/
chmod +x /var/cpanel/spamtitan/SpamTitanDomainsv2.sh
```

2. Edit the config file with your SpamTitan API details:

```
vi /var/cpanel/spamtitan/spamtitan.conf
```

At minimum, update `BASEURL` and `TOKEN` with your SpamTitan information.

3. Create the log file with appropriate permissions (the `checkmx` hook runs as the cPanel user, not root):

```
touch /var/log/spamtitan_hook.log
chmod 622 /var/log/spamtitan_hook.log
```

4. Register the hooks:

```
/usr/local/cpanel/bin/manage_hooks add script /var/cpanel/spamtitan/SpamTitanDomainsv2.sh
```

You should see:

```
Added hook for Whostmgr::Accounts::Create to hooks registry
Added hook for Whostmgr::Domain::park to hooks registry
Added hook for Whostmgr::Accounts::Remove to hooks registry
Added hook for Whostmgr::Domain::unpark to hooks registry
Added hook for Cpanel::Api2::Email::setmxcheck to hooks registry
```

## Uninstallation

```
/usr/local/cpanel/bin/manage_hooks del script /var/cpanel/spamtitan/SpamTitanDomainsv2.sh
```

## Verifying it works

Monitor the hook log:

```
tail -f /var/log/spamtitan_hook.log
```

Create a new account, add an alias domain, change MX routing, or terminate an account. You should see timestamped log entries showing each API call and its HTTP response code.

## Configuration

All settings are in `spamtitan.conf`. The script will not run without a valid config file.

| Setting | Default | Description |
|---|---|---|
| `BASEURL` | (required) | SpamTitan REST API domains endpoint, e.g. `https://spamtitan.example.com/restapi/domains` |
| `TOKEN` | (required) | SpamTitan REST API bearer token |
| `LOGFILE` | `/var/log/spamtitan_hook.log` | Log file path |
| `MAX_RETRIES` | `2` | Number of retries after initial API failure |
| `RETRY_DELAY` | `3` | Seconds between retries |
| `CURL_TIMEOUT` | `15` | Per-request timeout in seconds |
| `DEFAULT_QREPORT_ENABLED` | `true` | Enable quarantine reports for new domains |
| `DEFAULT_QREPORT_FREQUENCY` | `D` | Quarantine report frequency (D=daily, W=weekly) |
| `DEFAULT_QREPORT_CONTAINS` | `N` | Quarantine report contents (N=new, A=all) |
| `DEFAULT_AUTH_TYPE` | `imap` | Authentication type for new domains |
| `DEFAULT_IMAP_PORT` | `993` | IMAP port for authentication |
| `DEFAULT_IMAP_SECURE` | `true` | Use SSL for IMAP authentication |
| `DEFAULT_IMAP_ADDRESS_TYPE` | `user@domain` | IMAP address format |
| `ST_ADMIN_USER` | `SpamTitanAdmin` | Local part of the admin email created on new accounts |
| `ST_ADMIN_ROLE_ID` | `6` | SpamTitan role ID for Domain Administrator |


### Log file permission denied on MX routing changes

The `checkmx` hook (`Api2::Email::setmxcheck`) runs under the cPanel user context, not root. If the log file is owned by root with default permissions, the hook will fail with "Permission denied" errors in `/usr/local/cpanel/logs/error_log` and the API response JSON will leak to stdout, causing cPanel to flag it as invalid hook output.

Fix by setting the log file to 622 (owner read/write, others write-only):

```
touch /var/log/spamtitan_hook.log
chmod 622 /var/log/spamtitan_hook.log
```

This allows cPanel users to append log entries but not read the log contents.

## Version history

### v2.1 -- 4/6/26
- Added transfer/rebuild awareness: checks `killdns` flag on account removal to preserve SpamTitan settings when DNS is retained (manual cleanup required)
- Added automatic `SpamTitanAdmin@domain.com` mailbox provisioning and SpamTitan Domain Administrator role assignment on account creation
- Domain creation now checks if domain already exists in SpamTitan before creating (prevents duplicates, preserves existing settings)

### v2.0 -- 4/6/26
- Rewritten with external config file
- Added proper timestamped logging with severity levels
- Added HTTP response checking and retry logic on all API calls
- Fixed tmpfile race condition with mktemp
- Moved `--describe` handling before stdin read
- Removed `blocking:1` from pre-stage hooks (external API calls should not block cPanel operations)
- Fixed stdout leakage that caused cPanel to flag hook responses as invalid

### v1.0 -- 4/22/25
- Initial bash version using SpamTitan REST API v3
- Replaced PHP version due to `exec` being disabled on the webserver

### PHP version -- 11/5/23
- PHP script using SpamTitan REST API v3 with cPanel v110

## Disclaimers

- This script is provided as-is with no warranty
- We are not professional developers
- Test thoroughly in your environment before deploying to production
- We welcome contributions and improvements

Thank you to everyone who contributes to the world wide knowledge base. Without you, a lot of us would be lost.
