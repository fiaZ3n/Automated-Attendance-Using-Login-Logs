#!/bin/bash
# ============================================================
#  Automated Attendance System Using Login Logs
#  OS Project - Shell Scripting
# ============================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$BASE_DIR/logs"
REPORTS_DIR="$BASE_DIR/reports"
DATA_DIR="$BASE_DIR/data"
EXPORTS_DIR="$BASE_DIR/exports"
LOGIN_LOG="$DATA_DIR/login_records.log"
CONFIG_FILE="$BASE_DIR/config.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────
print_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║       AUTOMATED ATTENDANCE SYSTEM (Login Logs)       ║"
    echo "║              OS Project - Shell Scripting            ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

print_success() { echo -e "${GREEN}[✔] $1${RESET}"; }
print_error()   { echo -e "${RED}[✘] $1${RESET}"; }
print_info()    { echo -e "${CYAN}[i] $1${RESET}"; }
print_warn()    { echo -e "${YELLOW}[!] $1${RESET}"; }

timestamp()     { date '+%Y-%m-%d %H:%M:%S'; }
today()         { date '+%Y-%m-%d'; }

init_dirs() {
    mkdir -p "$LOGS_DIR" "$REPORTS_DIR" "$DATA_DIR" "$EXPORTS_DIR"
    [ ! -f "$LOGIN_LOG" ] && touch "$LOGIN_LOG"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
WORK_START=09:00
WORK_END=18:00
MIN_HOURS=8
LATE_THRESHOLD=09:15
HALF_DAY_HOURS=4
COMPANY_NAME=MyOrganization
EOF
    fi
    source "$CONFIG_FILE"
}

# ── Feature 1: Login / Logout Tracking ───────────────────
track_login() {
    print_header
    echo -e "${BOLD}── Login / Logout Tracking ──${RESET}\n"

    echo -n "Enter Employee ID   : "; read -r emp_id
    [ -z "$emp_id" ] && { print_error "Employee ID required."; sleep 2; return; }

    echo -n "Enter Employee Name : "; read -r emp_name
    [ -z "$emp_name" ] && { print_error "Name required."; sleep 2; return; }

    echo -e "\n  1) Login\n  2) Logout"
    echo -n "Select action [1/2] : "; read -r action

    local ts; ts=$(timestamp)
    local date; date=$(today)
    local time; time=$(date '+%H:%M:%S')
    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    local host; host=$(hostname)

    case "$action" in
        1)
            # Check duplicate login today
            if grep -q "^$date|$emp_id|LOGIN" "$LOGIN_LOG" 2>/dev/null; then
                print_warn "Employee $emp_id already logged in today."
                echo -n "Force new login? [y/N]: "; read -r confirm
                [ "$confirm" != "y" ] && sleep 2 && return
            fi
            echo "$date|$emp_id|$emp_name|LOGIN|$time|$ip|$host" >> "$LOGIN_LOG"
            print_success "LOGIN recorded for $emp_name ($emp_id) at $time"
            echo "$ts - LOGIN  - $emp_id ($emp_name) from $ip" >> "$LOGS_DIR/activity.log"
            ;;
        2)
            if ! grep -q "^$date|$emp_id|LOGIN" "$LOGIN_LOG" 2>/dev/null; then
                print_warn "No login record found for $emp_id today. Recording logout anyway."
            fi
            echo "$date|$emp_id|$emp_name|LOGOUT|$time|$ip|$host" >> "$LOGIN_LOG"
            print_success "LOGOUT recorded for $emp_name ($emp_id) at $time"
            echo "$ts - LOGOUT - $emp_id ($emp_name) from $ip" >> "$LOGS_DIR/activity.log"
            ;;
        *)
            print_error "Invalid option."
            sleep 2; return
            ;;
    esac

    # Show today's session so far
    echo -e "\n${BOLD}Today's sessions for $emp_id:${RESET}"
    echo -e "─────────────────────────────────────────"
    grep "^$date|$emp_id|" "$LOGIN_LOG" | while IFS='|' read -r d id name action t ip host; do
        printf "  %-8s  %s  (%s)\n" "$action" "$t" "$ip"
    done
    echo ""
    sleep 3
}

# ── Feature 2: Daily Attendance Generation ────────────────
generate_daily_attendance() {
    print_header
    echo -e "${BOLD}── Daily Attendance Report ──${RESET}\n"

    echo -n "Enter date [YYYY-MM-DD] (blank = today): "; read -r target_date
    [ -z "$target_date" ] && target_date=$(today)

    if ! echo "$target_date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        print_error "Invalid date format."; sleep 2; return
    fi

    local report_file="$REPORTS_DIR/attendance_${target_date}.txt"

    echo -e "\n${BOLD}Generating attendance for $target_date...${RESET}\n"

    {
        echo "============================================================"
        echo "  DAILY ATTENDANCE REPORT — $target_date"
        echo "  Generated : $(timestamp)"
        printf "  %-15s %s\n" "Company :" "${COMPANY_NAME:-MyOrganization}"
        echo "============================================================"
        printf "\n%-12s %-20s %-10s %-10s %-10s %-15s\n" \
               "EMP ID" "NAME" "LOGIN" "LOGOUT" "HOURS" "STATUS"
        echo "────────────────────────────────────────────────────────────"
    } > "$report_file"

    # Collect unique employee IDs for this date
    local emp_ids
    emp_ids=$(grep "^$target_date|" "$LOGIN_LOG" | cut -d'|' -f2 | sort -u)

    if [ -z "$emp_ids" ]; then
        echo "  No records found for $target_date." >> "$report_file"
        echo "============================================================" >> "$report_file"
        print_warn "No records found for $target_date."
        sleep 2; return
    fi

    local present=0 absent=0 late=0 half=0

    while IFS= read -r eid; do
        local emp_name login_time logout_time hours_worked status

        emp_name=$(grep "^$target_date|$eid|" "$LOGIN_LOG" | head -1 | cut -d'|' -f3)
        login_time=$(grep "^$target_date|$eid|.*|LOGIN|" "$LOGIN_LOG" | tail -1 | cut -d'|' -f5)
        logout_time=$(grep "^$target_date|$eid|.*|LOGOUT|" "$LOGIN_LOG" | tail -1 | cut -d'|' -f5)

        # Calculate hours worked
        if [ -n "$login_time" ] && [ -n "$logout_time" ]; then
            local login_sec logout_sec
            login_sec=$(echo "$login_time" | awk -F: '{ print ($1*3600)+($2*60)+$3 }')
            logout_sec=$(echo "$logout_time" | awk -F: '{ print ($1*3600)+($2*60)+$3 }')
            local diff=$(( logout_sec - login_sec ))
            hours_worked=$(echo "scale=2; $diff / 3600" | bc)

            # Determine status
            local late_sec
            late_sec=$(echo "${LATE_THRESHOLD:-09:15}" | awk -F: '{ print ($1*3600)+($2*60) }')
            local min_sec
            min_sec=$(echo "${MIN_HOURS:-8}" | awk '{ print $1*3600 }')
            local half_sec
            half_sec=$(echo "${HALF_DAY_HOURS:-4}" | awk '{ print $1*3600 }')

            if [ "$diff" -ge "$min_sec" ]; then
                if [ "$login_sec" -gt "$late_sec" ]; then
                    status="LATE"; ((late++))
                else
                    status="PRESENT"; ((present++))
                fi
            elif [ "$diff" -ge "$half_sec" ]; then
                status="HALF-DAY"; ((half++))
            else
                status="INSUFFICIENT"; ((absent++))
            fi
        elif [ -n "$login_time" ]; then
            logout_time="--:--:--"
            hours_worked="--"
            status="NO LOGOUT"
            ((present++))
        else
            login_time="--:--:--"
            logout_time="--:--:--"
            hours_worked="0.00"
            status="ABSENT"
            ((absent++))
        fi

        printf "%-12s %-20s %-10s %-10s %-10s %-15s\n" \
               "$eid" "$emp_name" "${login_time:0:8}" "${logout_time:0:8}" \
               "$hours_worked" "$status" >> "$report_file"

    done <<< "$emp_ids"

    {
        echo "────────────────────────────────────────────────────────────"
        echo ""
        echo "  SUMMARY"
        echo "  ──────────────────────────────"
        printf "  %-20s %d\n" "Total Employees:"  "$(( present + absent + late + half ))"
        printf "  %-20s %d\n" "Present:"          "$present"
        printf "  %-20s %d\n" "Late:"             "$late"
        printf "  %-20s %d\n" "Half-Day:"         "$half"
        printf "  %-20s %d\n" "Absent/Insuff:"    "$absent"
        echo ""
        echo "============================================================"
    } >> "$report_file"

    cat "$report_file"
    print_success "\nReport saved: $report_file"
    sleep 4
}

# ── Feature 3: CSV Export ─────────────────────────────────
export_csv() {
    print_header
    echo -e "${BOLD}── CSV Export ──${RESET}\n"

    echo "  1) Export all records"
    echo "  2) Export by date range"
    echo "  3) Export by employee"
    echo "  4) Export processed attendance (daily summary)"
    echo -n "\nSelect [1-4]: "; read -r choice

    local out_file

    case "$choice" in
        1)
            out_file="$EXPORTS_DIR/all_records_$(date +%Y%m%d_%H%M%S).csv"
            echo "Date,EmployeeID,Name,Action,Time,IP,Hostname" > "$out_file"
            sed 's/|/,/g' "$LOGIN_LOG" >> "$out_file"
            print_success "Exported: $out_file"
            ;;
        2)
            echo -n "Start date [YYYY-MM-DD]: "; read -r start
            echo -n "End   date [YYYY-MM-DD]: "; read -r end
            out_file="$EXPORTS_DIR/records_${start}_to_${end}.csv"
            echo "Date,EmployeeID,Name,Action,Time,IP,Hostname" > "$out_file"
            awk -F'|' -v s="$start" -v e="$end" '$1>=s && $1<=e' "$LOGIN_LOG" | sed 's/|/,/g' >> "$out_file"
            print_success "Exported: $out_file"
            ;;
        3)
            echo -n "Employee ID: "; read -r eid
            out_file="$EXPORTS_DIR/employee_${eid}_$(date +%Y%m%d).csv"
            echo "Date,EmployeeID,Name,Action,Time,IP,Hostname" > "$out_file"
            grep "|$eid|" "$LOGIN_LOG" | sed 's/|/,/g' >> "$out_file"
            print_success "Exported: $out_file"
            ;;
        4)
            out_file="$EXPORTS_DIR/attendance_summary_$(date +%Y%m%d_%H%M%S).csv"
            echo "Date,EmployeeID,Name,LoginTime,LogoutTime,HoursWorked,Status" > "$out_file"

            local dates
            dates=$(cut -d'|' -f1 "$LOGIN_LOG" | sort -u)

            while IFS= read -r d; do
                local emp_ids
                emp_ids=$(grep "^$d|" "$LOGIN_LOG" | cut -d'|' -f2 | sort -u)
                while IFS= read -r eid; do
                    local name login_t logout_t hours status
                    name=$(grep "^$d|$eid|" "$LOGIN_LOG" | head -1 | cut -d'|' -f3)
                    login_t=$(grep "^$d|$eid|.*|LOGIN|" "$LOGIN_LOG" | tail -1 | cut -d'|' -f5)
                    logout_t=$(grep "^$d|$eid|.*|LOGOUT|" "$LOGIN_LOG" | tail -1 | cut -d'|' -f5)

                    if [ -n "$login_t" ] && [ -n "$logout_t" ]; then
                        local ls ls2
                        ls=$(echo "$login_t" | awk -F: '{print ($1*3600)+($2*60)+$3}')
                        ls2=$(echo "$logout_t" | awk -F: '{print ($1*3600)+($2*60)+$3}')
                        hours=$(echo "scale=2; ($ls2-$ls)/3600" | bc)
                        status="PRESENT"
                        [ "$(echo "$hours < 4" | bc)" -eq 1 ] && status="HALF-DAY"
                    else
                        hours="0.00"; status="ABSENT"
                        [ -n "$login_t" ] && status="NO LOGOUT"
                    fi
                    echo "$d,$eid,$name,${login_t:---},${logout_t:---},$hours,$status" >> "$out_file"
                done <<< "$emp_ids"
            done <<< "$dates"

            print_success "Exported: $out_file"
            ;;
        *)
            print_error "Invalid choice."; sleep 2; return
            ;;
    esac

    local lines; lines=$(wc -l < "$out_file")
    print_info "Total rows (incl. header): $lines"
    sleep 3
}

# ── Feature 4: Summary Analytics ─────────────────────────
summary_analytics() {
    print_header
    echo -e "${BOLD}── Summary Analytics ──${RESET}\n"

    if [ ! -s "$LOGIN_LOG" ]; then
        print_warn "No data in login log."; sleep 2; return
    fi

    local total_records total_employees total_dates

    total_records=$(wc -l < "$LOGIN_LOG")
    total_employees=$(cut -d'|' -f2 "$LOGIN_LOG" | sort -u | wc -l)
    total_dates=$(cut -d'|' -f1 "$LOGIN_LOG" | sort -u | wc -l)

    echo -e "${BOLD}Global Statistics${RESET}"
    echo "─────────────────────────────────────────────"
    printf "  %-30s %s\n" "Total Log Entries:"      "$total_records"
    printf "  %-30s %s\n" "Unique Employees:"        "$total_employees"
    printf "  %-30s %s\n" "Days with Records:"       "$total_dates"
    echo ""

    # Most active days
    echo -e "${BOLD}Top 5 Most Active Days${RESET}"
    echo "─────────────────────────────────────────────"
    cut -d'|' -f1 "$LOGIN_LOG" | sort | uniq -c | sort -rn | head -5 | \
        awk '{ printf "  %-5s logins/logouts on %s\n", $1, $2 }'
    echo ""

    # Per-employee stats
    echo -e "${BOLD}Per-Employee Attendance Summary${RESET}"
    echo "─────────────────────────────────────────────"
    printf "  %-12s %-20s %-12s %-12s %-12s\n" \
           "EMP ID" "NAME" "LOGINS" "LOGOUTS" "DAYS ACTIVE"
    echo "  ────────────────────────────────────────────────────────"

    cut -d'|' -f2 "$LOGIN_LOG" | sort -u | while IFS= read -r eid; do
        local name logins logouts days
        name=$(grep "|$eid|" "$LOGIN_LOG" | head -1 | cut -d'|' -f3)
        logins=$(grep "|$eid|.*|LOGIN|" "$LOGIN_LOG" | wc -l)
        logouts=$(grep "|$eid|.*|LOGOUT|" "$LOGIN_LOG" | wc -l)
        days=$(grep "|$eid|" "$LOGIN_LOG" | cut -d'|' -f1 | sort -u | wc -l)
        printf "  %-12s %-20s %-12s %-12s %-12s\n" "$eid" "$name" "$logins" "$logouts" "$days"
    done

    echo ""

    # Average working hours (employees with both login+logout)
    echo -e "${BOLD}Average Working Hours per Employee${RESET}"
    echo "─────────────────────────────────────────────"

    cut -d'|' -f2 "$LOGIN_LOG" | sort -u | while IFS= read -r eid; do
        local dates
        dates=$(grep "|$eid|.*|LOGIN|" "$LOGIN_LOG" | cut -d'|' -f1 | sort -u)
        local total_secs=0 count=0

        while IFS= read -r d; do
            local lt lot
            lt=$(grep "^$d|$eid|.*|LOGIN|" "$LOGIN_LOG"  | tail -1 | cut -d'|' -f5)
            lot=$(grep "^$d|$eid|.*|LOGOUT|" "$LOGIN_LOG" | tail -1 | cut -d'|' -f5)
            if [ -n "$lt" ] && [ -n "$lot" ]; then
                local ls ls2
                ls=$(echo "$lt"  | awk -F: '{print ($1*3600)+($2*60)+$3}')
                ls2=$(echo "$lot" | awk -F: '{print ($1*3600)+($2*60)+$3}')
                total_secs=$(( total_secs + ls2 - ls ))
                ((count++))
            fi
        done <<< "$dates"

        if [ "$count" -gt 0 ]; then
            local avg_h
            avg_h=$(echo "scale=2; $total_secs / $count / 3600" | bc)
            local name
            name=$(grep "|$eid|" "$LOGIN_LOG" | head -1 | cut -d'|' -f3)
            printf "  %-12s %-20s %s hrs/day (over %d days)\n" "$eid" "$name" "$avg_h" "$count"
        fi
    done

    echo ""

    # Late arrivals
    echo -e "${BOLD}Late Arrival Count (after ${LATE_THRESHOLD:-09:15})${RESET}"
    echo "─────────────────────────────────────────────"
    local late_thresh_sec
    late_thresh_sec=$(echo "${LATE_THRESHOLD:-09:15}" | awk -F: '{ print ($1*3600)+($2*60) }')

    cut -d'|' -f2 "$LOGIN_LOG" | sort -u | while IFS= read -r eid; do
        local late_count=0
        local name
        name=$(grep "|$eid|" "$LOGIN_LOG" | head -1 | cut -d'|' -f3)
        while IFS= read -r lt; do
            local ls
            ls=$(echo "$lt" | awk -F: '{print ($1*3600)+($2*60)+$3}')
            [ "$ls" -gt "$late_thresh_sec" ] && ((late_count++))
        done < <(grep "|$eid|.*|LOGIN|" "$LOGIN_LOG" | cut -d'|' -f5)
        [ "$late_count" -gt 0 ] && \
            printf "  %-12s %-20s %d late arrival(s)\n" "$eid" "$name" "$late_count"
    done

    echo ""
    echo "─────────────────────────────────────────────"
    print_info "Analytics complete."
    sleep 5
}

# ── Feature 5: Simulate / Seed Sample Data ────────────────
seed_sample_data() {
    print_header
    echo -e "${BOLD}── Seed Sample Login Data ──${RESET}\n"
    print_warn "This will add sample log entries for testing."
    echo -n "Continue? [y/N]: "; read -r confirm
    [ "$confirm" != "y" ] && return

    local employees=(
        "E001|Alice Johnson"
        "E002|Bob Smith"
        "E003|Carol White"
        "E004|David Brown"
        "E005|Eve Davis"
    )

    for i in 0 1 2 3 4; do
        local d; d=$(date -d "-$i days" '+%Y-%m-%d' 2>/dev/null || date -v"-${i}d" '+%Y-%m-%d')
        for emp in "${employees[@]}"; do
            local eid name
            eid=$(echo "$emp" | cut -d'|' -f1)
            name=$(echo "$emp" | cut -d'|' -f2)
            # Random login between 08:45 and 09:30
            local lh lm; lh=9; lm=$(( RANDOM % 30 ))
            local login_t; login_t=$(printf "%02d:%02d:%02d" $lh $lm $(( RANDOM % 60 )))
            # Random logout between 17:00 and 18:30
            local loh lom; loh=$(( 17 + RANDOM % 2 )); lom=$(( RANDOM % 60 ))
            local logout_t; logout_t=$(printf "%02d:%02d:%02d" $loh $lom $(( RANDOM % 60 )))

            echo "$d|$eid|$name|LOGIN|$login_t|192.168.1.$(( RANDOM % 50 + 10 ))|workstation-$eid" >> "$LOGIN_LOG"
            echo "$d|$eid|$name|LOGOUT|$logout_t|192.168.1.$(( RANDOM % 50 + 10 ))|workstation-$eid" >> "$LOGIN_LOG"
        done
    done

    print_success "Sample data seeded for 5 employees across 5 days."
    sleep 2
}

# ── Feature 6: View Raw Logs ──────────────────────────────
view_logs() {
    print_header
    echo -e "${BOLD}── Raw Login Log ──${RESET}\n"

    if [ ! -s "$LOGIN_LOG" ]; then
        print_warn "Log file is empty."; sleep 2; return
    fi

    printf "%-12s %-10s %-20s %-8s %-10s %-16s\n" \
           "DATE" "EMP ID" "NAME" "ACTION" "TIME" "IP"
    echo "──────────────────────────────────────────────────────────────────"

    tail -40 "$LOGIN_LOG" | while IFS='|' read -r date id name action time ip host; do
        printf "%-12s %-10s %-20s %-8s %-10s %-16s\n" \
               "$date" "$id" "$name" "$action" "$time" "$ip"
    done

    echo ""
    local total; total=$(wc -l < "$LOGIN_LOG")
    print_info "Showing last 40 of $total records."
    sleep 4
}

# ── Feature 7: System Settings ────────────────────────────
configure_settings() {
    print_header
    echo -e "${BOLD}── System Configuration ──${RESET}\n"
    source "$CONFIG_FILE"

    echo -e "Current settings:\n"
    cat "$CONFIG_FILE"
    echo ""

    echo -n "Work start time  [HH:MM, current: $WORK_START]: "; read -r v
    [ -n "$v" ] && WORK_START="$v"

    echo -n "Work end time    [HH:MM, current: $WORK_END]: "; read -r v
    [ -n "$v" ] && WORK_END="$v"

    echo -n "Min hours/day   [current: $MIN_HOURS]: "; read -r v
    [ -n "$v" ] && MIN_HOURS="$v"

    echo -n "Late threshold  [HH:MM, current: $LATE_THRESHOLD]: "; read -r v
    [ -n "$v" ] && LATE_THRESHOLD="$v"

    echo -n "Half-day hours  [current: $HALF_DAY_HOURS]: "; read -r v
    [ -n "$v" ] && HALF_DAY_HOURS="$v"

    echo -n "Company name    [current: $COMPANY_NAME]: "; read -r v
    [ -n "$v" ] && COMPANY_NAME="$v"

    cat > "$CONFIG_FILE" <<EOF
WORK_START=$WORK_START
WORK_END=$WORK_END
MIN_HOURS=$MIN_HOURS
LATE_THRESHOLD=$LATE_THRESHOLD
HALF_DAY_HOURS=$HALF_DAY_HOURS
COMPANY_NAME=$COMPANY_NAME
EOF

    print_success "Settings saved."
    sleep 2
}

# ── Main Menu ─────────────────────────────────────────────
main_menu() {
    while true; do
        print_header
        source "$CONFIG_FILE" 2>/dev/null
        echo -e "  ${BOLD}Company:${RESET} ${COMPANY_NAME:-MyOrganization}   |   ${BOLD}Date:${RESET} $(today)   |   ${BOLD}Time:${RESET} $(date '+%H:%M:%S')\n"

        echo -e "  ${BOLD}MAIN MENU${RESET}"
        echo "  ─────────────────────────────────────────"
        echo "  1) Login / Logout Tracking"
        echo "  2) Generate Daily Attendance Report"
        echo "  3) CSV Export"
        echo "  4) Summary Analytics"
        echo "  5) View Raw Logs"
        echo "  6) Seed Sample Data (Testing)"
        echo "  7) System Configuration"
        echo "  8) Exit"
        echo "  ─────────────────────────────────────────"
        local total; total=$(wc -l < "$LOGIN_LOG" 2>/dev/null || echo 0)
        echo -e "  ${CYAN}Total log entries: $total${RESET}\n"

        echo -n "  Select option [1-8]: "; read -r opt

        case "$opt" in
            1) track_login ;;
            2) generate_daily_attendance ;;
            3) export_csv ;;
            4) summary_analytics ;;
            5) view_logs ;;
            6) seed_sample_data ;;
            7) configure_settings ;;
            8) echo -e "\n${GREEN}Goodbye!${RESET}\n"; exit 0 ;;
            *) print_error "Invalid option."; sleep 1 ;;
        esac
    done
}

# ── Entry Point ───────────────────────────────────────────
init_dirs
main_menu
