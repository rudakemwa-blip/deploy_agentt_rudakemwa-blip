#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$ROOT_DIR/templates"
PROJECT_DIR=""
DEPLOYING=false

handle_interrupt() {
    local signal_name="$1"
    local archive="${PROJECT_DIR}_archive.zip"

    trap - INT TSTP
    echo
    echo "Deployment interrupted by $signal_name."

    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        rm -f "$archive"
        if zip -rq "$archive" "$PROJECT_DIR"; then
            echo "Archive created: $archive"
            rm -rf -- "$PROJECT_DIR"
            echo "Incomplete project removed."
        else
            echo "Archive failed. Project directory kept."
        fi
    fi
    exit 1
}

run_app() {
    local project="$1"
    if [[ ! -f "$project/attendance_checker.py" ]]; then
        echo "Error: attendance_checker.py not found in $project"
        return 1
    fi
    cd "$project" || return 1
    python3 attendance_checker.py
}

archive_logs() {
    local project="$1"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    if [[ ! -d "$project" ]]; then
        echo "Error: Project not found: $project"
        return 1
    fi

    mkdir -p "$project/archives/attendance" "$project/archives/absent"

    if [[ -f "$project/reports/attendance.log" ]]; then
        cp "$project/reports/attendance.log" \
            "$project/archives/attendance/attendance_$timestamp.log"
        echo "Attendance log archived."
    else
        echo "No attendance.log found at $project/reports/attendance.log"
    fi

    if [[ -f "$project/reports/absent.log" ]]; then
        cp "$project/reports/absent.log" \
            "$project/archives/absent/absent_$timestamp.log"
        echo "Absent log archived."
    else
        echo "No absent.log found at $project/reports/absent.log"
    fi
}

deploy_app() {
    local name target choice threshold

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: Python 3 is required."
        return 1
    fi

    if ! command -v zip >/dev/null 2>&1; then
        echo "Error: zip is required."
        return 1
    fi

    python3 --version

    for file in attendance_checker.py config.json assets.csv; do
        if [[ ! -f "$TEMPLATE_DIR/$file" ]]; then
            echo "Error: Missing template: $TEMPLATE_DIR/$file"
            return 1
        fi
    done

    read -r -p "Enter a project name: " name
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Use only letters, numbers, underscores, or hyphens."
        return 1
    fi

    target="$ROOT_DIR/attendance_tracker_$name"
    PROJECT_DIR="$target"

    if [[ -e "$target" ]]; then
        read -r -p "Project exists. Replace it? (y/n): " choice
        if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
            echo "Deployment cancelled."
            return 1
        fi
        rm -rf -- "$target" || return 1
    fi

    trap 'handle_interrupt SIGINT' INT
    trap 'handle_interrupt SIGTSTP' TSTP
    DEPLOYING=true

    mkdir -p "$target/Helpers" "$target/reports" || return 1
    cp "$TEMPLATE_DIR/attendance_checker.py" "$target/" || return 1
    cp "$TEMPLATE_DIR/config.json" "$target/Helpers/config.json" || return 1
    cp "$TEMPLATE_DIR/assets.csv" "$target/Helpers/assets.csv" || return 1

    echo
    echo "Choose roster setup:"
    echo "1. Use the provided CSV roster"
    echo "2. Use a small sample roster"
    read -r -p "Choose 1 or 2: " choice

    if [[ "$choice" == "2" ]]; then
    cat > "$target/Helpers/assets.csv" <<'CSV'
Names,Email,Attendance Count,Absence Count
Alice Johnson,alice@example.com,8,2
Brian Smith,brian@example.com,9,1
Chantal Uwase,chantal@example.com,5,5
CSV
        sed -i 's/"total_sessions"[[:space:]]*:[[:space:]]*[0-9]*/"total_sessions": 1/' \
            "$target/Helpers/config.json"
    elif [[ "$choice" != "1" ]]; then
        echo "Invalid choice."
        return 1
    fi

    read -r -p "Enter warning threshold (0-100): " threshold
    if [[ ! "$threshold" =~ ^[0-9]+$ ]] || (( threshold > 100 )); then
        echo "Threshold must be a whole number from 0 to 100."
        return 1
    fi

    read -r -p "Enter critical threshold (0-100): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice > 100 )); then
        echo "Threshold must be a whole number from 0 to 100."
        return 1
    fi

    if (( choice > threshold )); then
        echo "Critical threshold should not exceed warning threshold."
        return 1
    fi

    sed -i "s/\"warning_threshold\"[[:space:]]*:[[:space:]]*[0-9]*/\"warning_threshold\": $threshold/" \
        "$target/Helpers/config.json"
    sed -i "s/\"critical_threshold\"[[:space:]]*:[[:space:]]*[0-9]*/\"critical_threshold\": $choice/" \
        "$target/Helpers/config.json"

    chmod +x "$target/attendance_checker.py"
    chmod 600 "$target/Helpers/config.json"

    if [[ ! -s "$target/Helpers/assets.csv" || ! -s "$target/Helpers/config.json" ]]; then
        echo "Error: Required files are empty."
        return 1
    fi

    DEPLOYING=false
    trap - INT TSTP
    echo "Deployment complete: $target"
    run_app "$target"
}

show_menu() {
    echo
    echo "===== Attendance Deployment Agent ====="
    echo "1. deploy"
    echo "2. run"
    echo "3. archive"
    echo "4. exit"
    read -r -p "Choose an option: " action

    case "$action" in
        1|deploy)
            deploy_app
            ;;
        2|run)
            read -r -p "Project folder name (e.g. attendance_tracker_demo): " name
            run_app "$ROOT_DIR/$name"
            ;;
        3|archive)
            read -r -p "Project folder name (e.g. attendance_tracker_demo): " name
            archive_logs "$ROOT_DIR/$name"
            ;;
        4|exit)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
}

show_menu
