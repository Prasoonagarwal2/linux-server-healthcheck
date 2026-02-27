# linux-server-healthcheck
Bash script to generate automated Linux server health check reports

This script collects:
- Server Name
- FQDN
- Status
- Connectivity Error
- Python Version
- IP Address
- OS Version
- Date & Time
- Uptime
- Kernel Version
- Swap Memory
- Swap Utilization
- Last Patch Date
- SSHD Status
- Centrify Status
- SSSD Status
- Icinga2 Status
- CrowdStrike Status
- Filesystem Count
- CPU Count
- Total Memory
- CPU Usage %
- Satellite Subscription
- Top CPU User
- Top Mem User
- Filesystem Details
- Top 10 Processes
- Missing FSTAB Entries
- AD Info

Output: CSV report generated in the user directory.

OUTPUT_CSV="Linux_Health_Check_Report_${TIMESTAMP}.csv"
