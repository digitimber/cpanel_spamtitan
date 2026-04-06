#!/bin/bash

# SpamTitan Hook Script for cPanel Domain Lifecycle Events
# Author: Russ Lohman
# Version: 2.1
# Usage: Hooked via manage_hooks with the appropriate --script-args or --manual
# Events: Accounts::Create, Accounts::Remove, Domain::park, Domain::unpark, Api2::Email::setmxcheck

CONF_FILE="/var/cpanel/spamtitan/spamtitan.conf"

# -------------------------------------------------------------------
# Load configuration
# -------------------------------------------------------------------
if [[ ! -f "$CONF_FILE" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SpamTitan] [FATAL] Config file not found: $CONF_FILE"
    exit 1
fi

source "$CONF_FILE"

# Validate required config values
for var in BASEURL TOKEN; do
    if [[ -z "${!var}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [SpamTitan] [FATAL] Missing required config value: $var"
        exit 1
    fi
done

# Defaults for optional config values
LOGFILE="${LOGFILE:-/var/log/spamtitan_hook.log}"
MAX_RETRIES="${MAX_RETRIES:-2}"
RETRY_DELAY="${RETRY_DELAY:-3}"
CURL_TIMEOUT="${CURL_TIMEOUT:-15}"
DEFAULT_QREPORT_ENABLED="${DEFAULT_QREPORT_ENABLED:-true}"
DEFAULT_QREPORT_FREQUENCY="${DEFAULT_QREPORT_FREQUENCY:-D}"
DEFAULT_QREPORT_CONTAINS="${DEFAULT_QREPORT_CONTAINS:-N}"
DEFAULT_AUTH_TYPE="${DEFAULT_AUTH_TYPE:-imap}"
DEFAULT_IMAP_PORT="${DEFAULT_IMAP_PORT:-993}"
DEFAULT_IMAP_SECURE="${DEFAULT_IMAP_SECURE:-true}"
DEFAULT_IMAP_ADDRESS_TYPE="${DEFAULT_IMAP_ADDRESS_TYPE:-user@domain}"
ST_ADMIN_USER="${ST_ADMIN_USER:-stadmin}"
ST_ADMIN_ROLE_ID="${ST_ADMIN_ROLE_ID:-6}"

# Base URL for non-domain ST API calls (strip /domains from BASEURL)
ST_API_BASE="${BASEURL%/domains}"

# -------------------------------------------------------------------
# Handle --describe before reading stdin (avoids blocking)
# -------------------------------------------------------------------
if [[ "$1" == "--describe" ]]; then
    echo '[
        {"category":"Whostmgr","event":"Accounts::Create","stage":"post","hook":"'"$0"' createaccount","exectype":"script"},
        {"category":"Whostmgr","event":"Domain::park","stage":"post","hook":"'"$0"' domainpark","exectype":"script"},
        {"category":"Whostmgr","event":"Accounts::Remove","stage":"pre","hook":"'"$0"' removeaccount","exectype":"script"},
        {"category":"Whostmgr","event":"Domain::unpark","stage":"pre","hook":"'"$0"' domainunpark","exectype":"script"},
        {"category":"Cpanel","event":"Api2::Email::setmxcheck","stage":"post","hook":"'"$0"' checkmx","exectype":"script"}
    ]'
    exit 0
fi

# -------------------------------------------------------------------
# Logging
# -------------------------------------------------------------------
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SpamTitan] [$level] $*" >> "$LOGFILE"
}

# -------------------------------------------------------------------
# API helper with retry and response checking
# -------------------------------------------------------------------
api_call() {
    local method="$1"
    local url="$2"
    local data="$3"
    local content_type="${4:-application/x-www-form-urlencoded}"
    local attempt=0
    local http_code
    local tmpout

    API_RESPONSE=""
    tmpout=$(mktemp /tmp/st_api_XXXXXX)

    while (( attempt <= MAX_RETRIES )); do
        if (( attempt > 0 )); then
            log "WARN" "Retry $attempt/$MAX_RETRIES for $method $url"
            sleep "$RETRY_DELAY"
        fi

        if [[ -n "$data" ]]; then
            http_code=$(curl -sk -X "$method" \
                --max-time "$CURL_TIMEOUT" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: $content_type" \
                -d "$data" \
                -o "$tmpout" \
                -w '%{http_code}' \
                "$url" 2>/dev/null)
        else
            http_code=$(curl -sk -X "$method" \
                --max-time "$CURL_TIMEOUT" \
                -H "Authorization: Bearer $TOKEN" \
                -o "$tmpout" \
                -w '%{http_code}' \
                "$url" 2>/dev/null)
        fi

        local curl_exit=$?

        if (( curl_exit != 0 )); then
            log "ERROR" "curl failed (exit $curl_exit) for $method $url"
            (( attempt++ ))
            continue
        fi

        API_RESPONSE=$(cat "$tmpout")
        rm -f "$tmpout"

        case "$http_code" in
            2[0-9][0-9])
                log "INFO" "$method $url -> HTTP $http_code"
                return 0
                ;;
            404)
                log "WARN" "$method $url -> HTTP 404 (not found)"
                return 2
                ;;
            429)
                log "WARN" "$method $url -> HTTP 429 (rate limited)"
                (( attempt++ ))
                sleep "$RETRY_DELAY"
                continue
                ;;
            *)
                log "ERROR" "$method $url -> HTTP $http_code"
                log "ERROR" "Response body: $API_RESPONSE"
                (( attempt++ ))
                continue
                ;;
        esac
    done

    rm -f "$tmpout"
    log "ERROR" "All retries exhausted for $method $url"
    return 1
}

# -------------------------------------------------------------------
# Provision stadmin email and ST domain admin
# -------------------------------------------------------------------
provision_stadmin() {
    local domain="$1"
    local domain_id="$2"
    local cpuser="$3"
    local cppass="$4"
    local admin_email="${ST_ADMIN_USER}@${domain}"

    log "INFO" "Provisioning ST admin: $admin_email"

    # Create the stadmin mailbox in cPanel
    uapi --user="$cpuser" Email add_pop \
        email="$ST_ADMIN_USER" \
        password="$cppass" \
        quota=0 \
        --output=json > /dev/null 2>&1

    if (( $? != 0 )); then
        log "WARN" "Failed to create mailbox $admin_email in cPanel"
        return 1
    fi

    log "INFO" "Mailbox $admin_email created in cPanel"

    # Check if the user already exists in ST
    api_call GET "$ST_API_BASE/users/$admin_email"
    if (( $? == 0 )); then
        log "INFO" "User $admin_email already exists in SpamTitan, skipping ST user creation"
        return 0
    fi

    # Create user in ST with domain admin role
    api_call POST "$ST_API_BASE/users" \
        "{\"email\":\"$admin_email\",\"roles\":[{\"id\":$ST_ADMIN_ROLE_ID,\"domain_id\":$domain_id}]}" \
        "application/json"

    if (( $? != 0 )); then
        log "WARN" "Mailbox $admin_email created but ST domain admin setup failed"
        return 1
    fi

    log "INFO" "ST domain admin $admin_email provisioned (domain_id: $domain_id)"
    return 0
}

# -------------------------------------------------------------------
# Domain operations
# -------------------------------------------------------------------
create_domain() {
    local domain="$1"
    local user="$2"
    local pass="$3"

    # Check if domain already exists in ST (preserves settings on transfer/rebuild)
    api_call GET "$BASEURL/$domain"
    local rc=$?

    if (( rc == 0 )); then
        log "INFO" "Domain $domain already exists in SpamTitan, preserving existing settings"
        # Still provision stadmin if we have credentials (re-create after transfer)
        if [[ -n "$user" && -n "$pass" ]]; then
            local domain_id
            domain_id=$(echo "$API_RESPONSE" | jq -r '.id // empty')
            if [[ -n "$domain_id" ]]; then
                provision_stadmin "$domain" "$domain_id" "$user" "$pass"
            fi
        fi
        return 0
    fi

    log "INFO" "Creating domain: $domain"

    api_call POST "$BASEURL" \
        "{\"domain\":\"$domain\",\"destination\":\"mail.$domain\"}" \
        "application/json"

    if (( $? != 0 )); then
        log "ERROR" "Failed to create domain $domain"
        return 1
    fi

    # Capture domain_id from creation response
    local domain_id
    domain_id=$(echo "$API_RESPONSE" | jq -r '.id // empty')

    api_call PUT "$BASEURL/$domain/policy" \
        "qreport_enabled=$DEFAULT_QREPORT_ENABLED&qreport_frequency=$DEFAULT_QREPORT_FREQUENCY&qreport_contains=$DEFAULT_QREPORT_CONTAINS"

    if (( $? != 0 )); then
        log "WARN" "Domain $domain created but policy update failed"
    fi

    api_call PUT "$BASEURL/$domain/auth" \
        "auth_type=$DEFAULT_AUTH_TYPE&imap[server]=mail.$domain&imap[port]=$DEFAULT_IMAP_PORT&imap[secure]=$DEFAULT_IMAP_SECURE&imap[address_type]=$DEFAULT_IMAP_ADDRESS_TYPE"

    if (( $? != 0 )); then
        log "WARN" "Domain $domain created but auth config failed"
    fi

    # Provision stadmin if we have credentials (only on createaccount)
    if [[ -n "$user" && -n "$pass" && -n "$domain_id" ]]; then
        provision_stadmin "$domain" "$domain_id" "$user" "$pass"
    fi

    log "INFO" "Domain $domain setup complete"
    return 0
}

delete_domain() {
    local domain="$1"
    log "INFO" "Deleting domain: $domain"

    api_call GET "$BASEURL/$domain"
    local rc=$?

    if (( rc == 2 )); then
        log "WARN" "Domain $domain not found in SpamTitan, skipping delete"
        return 0
    elif (( rc != 0 )); then
        log "ERROR" "Failed to look up domain $domain"
        return 1
    fi

    local id
    id=$(echo "$API_RESPONSE" | jq -r '.id // empty')

    if [[ -z "$id" ]]; then
        log "WARN" "Domain $domain lookup returned no ID, skipping delete"
        return 0
    fi

    api_call DELETE "$BASEURL/$id"

    if (( $? != 0 )); then
        log "ERROR" "Failed to delete domain $domain (id: $id)"
        return 1
    fi

    log "INFO" "Domain $domain deleted (id: $id)"
    return 0
}

# -------------------------------------------------------------------
# Read stdin and parse event data
# -------------------------------------------------------------------
ACTION="$1"
STDIN_DATA=$(cat)
CURUSER=$(echo "$STDIN_DATA" | jq -r '.data.user // empty')
CURDOMAIN=$(echo "$STDIN_DATA" | jq -r '.data.domain // .data.new_domain // .data.args.domain // empty')
CURPASS=$(echo "$STDIN_DATA" | jq -r '.data.pass // empty')
KILLDNS=$(echo "$STDIN_DATA" | jq -r '.data.killdns // empty')
IS_LOCAL=$(echo "$STDIN_DATA" | jq -r '.data.output[0].local // 0')

log "INFO" "Hook fired: action=$ACTION user=$CURUSER domain=$CURDOMAIN"

# -------------------------------------------------------------------
# Event handlers
# -------------------------------------------------------------------
case "$ACTION" in
    createaccount)
        log "INFO" "Create account event for domain $CURDOMAIN"
        create_domain "$CURDOMAIN" "$CURUSER" "$CURPASS"
        ;;

    removeaccount)
        log "INFO" "Remove account event for user $CURUSER"

        # killdns: 0 = keep DNS (transfer/rebuild), 1 = kill DNS (permanent removal)
        if [[ "$KILLDNS" == "0" ]]; then
            log "INFO" "killdns=0 (DNS retained), preserving SpamTitan settings for user $CURUSER"
        else
            log "INFO" "killdns=1 (DNS removed), deleting SpamTitan domains for user $CURUSER"
            TMPFILE=$(mktemp /tmp/st_domains_XXXXXX.json)

            uapi --user="$CURUSER" DomainInfo list_domains --output=json > "$TMPFILE" 2>/dev/null

            if [[ ! -s "$TMPFILE" ]]; then
                log "ERROR" "Failed to fetch domain list for user $CURUSER"
                rm -f "$TMPFILE"
                exit 1
            fi

            MAIN=$(jq -r '.result.data.main_domain // empty' "$TMPFILE")
            PARKED=$(jq -r '.result.data.parked_domains[]?' "$TMPFILE")
            ADDONS=$(jq -r '.result.data.addon_domains[]?' "$TMPFILE")

            ALL_DOMAINS=($MAIN $PARKED $ADDONS)

            log "INFO" "Removing ${#ALL_DOMAINS[@]} domain(s) for user $CURUSER"

            for domain in "${ALL_DOMAINS[@]}"; do
                delete_domain "$domain"
            done

            rm -f "$TMPFILE"
        fi
        ;;

    domainpark)
        log "INFO" "Domain park event for $CURDOMAIN"
        create_domain "$CURDOMAIN"
        ;;

    domainunpark)
        log "INFO" "Domain unpark event for $CURDOMAIN"
        delete_domain "$CURDOMAIN"
        ;;

    checkmx)
        if [[ "$IS_LOCAL" == "1" ]]; then
            log "INFO" "MX set to local for $CURDOMAIN, adding domain"
            create_domain "$CURDOMAIN"
        else
            log "INFO" "MX set to remote for $CURDOMAIN, removing domain"
            delete_domain "$CURDOMAIN"
        fi
        ;;

    *)
        log "ERROR" "Unknown action: $ACTION (user=$CURUSER domain=$CURDOMAIN)"
        exit 1
        ;;
esac

exit 0
