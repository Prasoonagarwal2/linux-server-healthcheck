#!/bin/bash

USER="username_here"
PASSWORD="your_password_here"  # <-- Replace securely or prompt

echo
SERVER_LIST="server_list.txt"
TIMESTAMP=$(date +"%d-%m-%Y_%H_%M_%S")
OUTPUT_CSV="Linux_Health_Check_Report_${TIMESTAMP}.csv"

# CSV Header
echo "Server Name,FQDN,Status,Connectivity Error,Python Version,IP Address,OS Version,Date & Time,Uptime,Kernel Version,Swap Memory,Swap Utilization,Last Patch Date,SSHD Status,Centrify Status,SSSD Status,Icinga2 Status,CrowdStrike Status,Filesystem Count,CPU Count,Total Memory,CPU Usage %,Satellite Subscription,Top CPU User,Top Mem User,Filesystem Details,Top 10 Processes,Missing FSTAB Entries,AD Info" > "$OUTPUT_CSV"

# Count total servers
TOTAL_SERVERS=$(grep -cvE '^\s*#|^$' "$SERVER_LIST")
COUNT=0

# Loop through each server
while read -r HOST; do
    [[ -z "$HOST" || "$HOST" =~ ^# ]] && continue
    COUNT=$((COUNT + 1))
    echo "Processing $HOST... ($COUNT/$TOTAL_SERVERS)"

    OUTPUT=$(timeout 60 sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USER@$HOST" bash << 'EOF'
        # --- Variables ---
        SERVER_NAME=$(hostname)
        FQDN=$(hostname -f)
        STATUS="Online"
        CONNECTIVITY_ERROR="Connection successful"

        PYTHON_VERSION=$(python3 --version 2>/dev/null || python --version 2>/dev/null || echo "Not Installed")
        IP_ADDRESS=$(hostname -I | awk '{print $1}')

        # --- OS Version detection ---
        if [[ -f /etc/redhat-release ]]; then
            RAW=$(awk -F'release ' '{print $2}' /etc/redhat-release)
            OS_VENDOR="Redhat"
            OS_VERSION_NUM=$(echo "$RAW" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
            OS_VERSION="${OS_VENDOR} ${OS_VERSION_NUM}"
        elif [[ -f /etc/os-release ]]; then
            RAW=$(grep -w PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
            OS_VENDOR=$(echo "$RAW" | awk '{print $1}')
            OS_VERSION_NUM=$(echo "$RAW" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
            OS_VERSION="${OS_VENDOR} ${OS_VERSION_NUM}"
        else
            OS_VERSION="Unknown"
        fi

        DATETIME=$(date)
        UPTIME=$(uptime)

        KERNEL_VERSION=$(uname -r)

        SWAP_TOTAL=$(free -h | awk '/Swap/ {print $2}')
        SWAP_USED=$(free -h | awk '/Swap/ {print $3}')
        SWAP_UTIL="${SWAP_USED} / ${SWAP_TOTAL}"

        # --- Last patch date (last kernel install) ---
        if rpm -q --last kernel &>/dev/null; then
            LAST_PATCH_DATE=$(rpm -q --last kernel | head -1 | awk '{$1=""; sub(/^ /, ""); print}' | \
                xargs -I{} date -d "{}" +"%Y-%m-%d %H:%M:%S")
        else
            LAST_PATCH_DATE="Unavailable"
        fi

        # --- Flexible service checker ---
        service_status() {
            SERVICE_NAME="$1"
            if command -v systemctl &>/dev/null; then
                STATUS=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null)
                [[ "$STATUS" == "active" ]] && echo "Running" || echo "Not Running"
            elif command -v service &>/dev/null; then
                service "$SERVICE_NAME" status &>/dev/null
                [[ $? -eq 0 ]] && echo "Running" || echo "Not Running"
            else
                echo "Unknown"
            fi
        }

        SSHD_STATUS=$(service_status sshd)
        CENTRIFY_STATUS=$(service_status centrifydc)
        SSSD_STATUS=$(service_status sssd)
        ICINGA_STATUS=$(service_status icinga2)
        CROWDSTRIKE_STATUS=$(service_status falcon-sensor)

        FS_COUNT=$(mount | wc -l)
        CPU_COUNT=$(nproc)
        TOTAL_MEM=$(free -h | awk '/Mem/ {print $2}')

        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk '{printf "%.1f%%", $1}')
        CPU_USAGE="CPU:${CPU_USAGE}"  # Force text alignment

        # --- Satellite Subscription info ---
        if command -v subscription-manager &>/dev/null; then
		if command -v dzdo &>/dev/null; then
			SAT_SUB=$(dzdo subscription-manager identity 2>/dev/null | tr '\n' ' ' | sed 's/"/""/g')
		elif command -v sudo &>/dev/null; then
			SAT_SUB=$(sudo subscription-manager identity 2>/dev/null | tr '\n' ' ' | sed 's/"/""/g')
		else
			SAT_SUB=$(subscription-manager identity 2>/dev/null | tr '\n' ' ' | sed 's/"/""/g')
		fi
			[[ -z "$SAT_SUB" ]] && SAT_SUB="Not Registered"
		else
			SAT_SUB="Not Installed"
		fi

        # --- Top users by CPU and memory ---
        TOP_CPU_USER=$(ps -eo user,%cpu --sort=-%cpu | awk 'NR==2 {printf "%s:%.1f%%", $1, $2}')
        TOP_MEM_USER=$(ps -eo user,%mem --sort=-%mem | awk 'NR==2 {printf "%s:%.1f%%", $1, $2}')

        # --- Filesystem details ---
        FS_DETAILS=$(df -h | awk 'NR>1 {print $1 ":" $6 ":" $5}' | paste -sd ";" -)

        TOP_PROCS=$(ps -eo comm,%cpu,%mem --sort=-%cpu | head -n 11 | awk 'NR>1 {printf "%s,%.1f,%.1f|", $1, $2, $3}' | sed 's/|$//')

        MOUNTED_NFS_CIFS=$(mount | grep -Ei 'type (nfs|cifs)' || true)
        if [[ -n "$MOUNTED_NFS_CIFS" ]]; then
            FSTAB_ENTRIES=$(grep -Ei 'nfs|cifs' /etc/fstab | paste -sd ";" -)
        else
            FSTAB_ENTRIES="No NFS/CIFS share has been mounted on the server"
        fi

        if command -v adinfo &>/dev/null; then
            AD_INFO=$(adinfo | sed ':a;N;$!ba;s/\n/ | /g' | sed 's/"/""/g')
        else
            AD_INFO="adinfo command not found"
        fi

        # --- Final CSV-safe output ---
        echo "\"$SERVER_NAME\",\"$FQDN\",\"$STATUS\",\"$CONNECTIVITY_ERROR\",\"$PYTHON_VERSION\",\"$IP_ADDRESS\",\"$OS_VERSION\",\"$DATETIME\",\"$UPTIME\",\"$KERNEL_VERSION\",\"$SWAP_TOTAL\",\"$SWAP_UTIL\",\"$LAST_PATCH_DATE\",\"$SSHD_STATUS\",\"$CENTRIFY_STATUS\",\"$SSSD_STATUS\",\"$ICINGA_STATUS\",\"$CROWDSTRIKE_STATUS\",\"$FS_COUNT\",\"CPU:${CPU_COUNT}\",\"$TOTAL_MEM\",\"$CPU_USAGE\",\"$SAT_SUB\",\"$TOP_CPU_USER\",\"$TOP_MEM_USER\",\"$FS_DETAILS\",\"$TOP_PROCS\",\"$FSTAB_ENTRIES\",\"$AD_INFO\""
EOF
    )

    # If SSH or connection fails
    if [ $? -ne 0 ]; then
        STATUS="Offline"
        CONNECTIVITY_ERROR="Unable to connect"
        echo "\"$HOST\",\"\",\"$STATUS\",\"$CONNECTIVITY_ERROR\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"" >> "$OUTPUT_CSV"
    else
        echo "$OUTPUT" >> "$OUTPUT_CSV"
    fi

    echo "✅ Completed $COUNT of $TOTAL_SERVERS servers."
    echo "--------------------------------------------"

done < "$SERVER_LIST"

echo "✅ Health_check complete. Output saved to: $OUTPUT_CSV"
