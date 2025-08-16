#!/usr/bin/env bash

# Preserve the original working directory
ORIGINAL_PWD=$(pwd)

# Find all problem directories (nppe_* and sample) in the current directory
# Use -maxdepth 1 to only look in immediate subdirectories.
# Use -print0 and xargs -0 to handle spaces in directory names, and sort them.
find . -maxdepth 1 -type d \( -name "nppe_*" -o -name "sample" \) -print0 | sort -z | while IFS= read -r -d $'\0' PROBLEM_DIR; do
    # Skip the current directory itself if it somehow matches
    [ "$PROBLEM_DIR" = "." ] && continue

    # Change into the problem directory
    pushd "$PROBLEM_DIR" > /dev/null || { echo "Error: Could not change into $PROBLEM_DIR" >&2; continue; }

    PROBLEM_NAME=$(basename "$PROBLEM_DIR")
    PRIMARY_SOLUTION_FILENAME=""
    IS_PRIMARY_EXECUTABLE=0 # Flag for primary solution file if it needs +x
    PRIMARY_SOLUTION_LOGIC=""
    FALLBACK_WRAPPER_TYPE="" # Defines if fallback needs a sed/awk wrapper or is plain bash

    case "$PROBLEM_NAME" in
        "nppe_1")
            PRIMARY_SOLUTION_FILENAME="datasets.sh"
            IS_PRIMARY_EXECUTABLE=1
            PRIMARY_SOLUTION_LOGIC=$(cat <<'EOF'
mkdir -p Dataset{A..E}/{train,test,validation}
touch Dataset{A..E}/{train,test,validation}/{metadata.yml,README.md}
EOF
)
            FALLBACK_WRAPPER_TYPE="bash"
            ;;
        "nppe_2")
            PRIMARY_SOLUTION_FILENAME="script.sh"
            IS_PRIMARY_EXECUTABLE=1
            PRIMARY_SOLUTION_LOGIC=$(cat <<'EOF'
sed -E 's/.*Price: <span class="item-price">Rs\. ([0-9]+).*, Qty: <span class="item-qty">([0-9]+).*/\1 \2/' | awk '{s+=$1*$2} END{print s}'
EOF
)
            FALLBACK_WRAPPER_TYPE="bash"
            ;;
        "nppe_3")
            PRIMARY_SOLUTION_FILENAME="grades.sh"
            IS_PRIMARY_EXECUTABLE=1
            PRIMARY_SOLUTION_LOGIC=$(cat <<'EOF'
awk -F',' '
NR==1 { next }
{
    name = $2
    marks = $3
    grade = ""
    marks < 50 && grade = "U"
    marks >= 50 && marks < 60 && grade = "D"
    marks >= 60 && marks < 70 && grade = "C"
    marks >= 70 && marks < 80 && grade = "B"
    marks >= 80 && marks < 90 && grade = "A"
    marks >= 90 && grade = "S"
    print name ": " grade
}
' results.csv
EOF
)
            FALLBACK_WRAPPER_TYPE="bash"
            ;;
        "nppe_4")
            PRIMARY_SOLUTION_FILENAME="employees.sed"
            IS_PRIMARY_EXECUTABLE=0 # sed script, not a bash executable
            PRIMARY_SOLUTION_LOGIC=$(cat <<'EOF'
s/, [0-9][0-9]*//
s/Developer/Senior Developer/g
EOF
)
            FALLBACK_WRAPPER_TYPE="sed"
            ;;
        "nppe_5")
            PRIMARY_SOLUTION_FILENAME="topper.awk"
            IS_PRIMARY_EXECUTABLE=0 # awk script, not a bash executable
            PRIMARY_SOLUTION_LOGIC=$(cat <<'EOF'
awk '
NR==1 { next }
{
    name = $1
    sum = 0
    count = 0
    for (i=2; i<=NF; i++) {
        sum += $i
        count++
    }
    average = sum / count
    if (average > max_avg) {
        max_avg = average
        topper_name = name
    }
}
END {
    print "Topper: " topper_name
}
'
EOF
)
            FALLBACK_WRAPPER_TYPE="awk"
            ;;
        "sample")
            PRIMARY_SOLUTION_FILENAME="script.sh"
            IS_PRIMARY_EXECUTABLE=1
            PRIMARY_SOLUTION_LOGIC=$(cat <<'EOF'
sha256sum "$1" | cut -d" " -f1
EOF
)
            FALLBACK_WRAPPER_TYPE="bash"
            ;;
        *)
            popd > /dev/null
            continue
            ;;
    esac

    # Create primary solution file
    echo "$PRIMARY_SOLUTION_LOGIC" > "$PRIMARY_SOLUTION_FILENAME"
    [ "$IS_PRIMARY_EXECUTABLE" -eq 1 ] && chmod +x "$PRIMARY_SOLUTION_FILENAME"

    # Create fallback scripts (always bash executables that wrap the logic)
    for FALLBACK_BASENAME in s.sh t.sh test.sh; do
        FALLBACK_CONTENT=""
        FALLBACK_SHEBANG="#!/usr/bin/env bash\n"

        case "$FALLBACK_WRAPPER_TYPE" in
            "bash")
                FALLBACK_CONTENT="$PRIMARY_SOLUTION_LOGIC"
                ;;
            "sed")
                FALLBACK_CONTENT=$(cat <<EOS
${FALLBACK_SHEBANG}sed -f /dev/stdin "\$@" <<'SED_EOF'
${PRIMARY_SOLUTION_LOGIC}
SED_EOF
EOS
)
                ;;
            "awk")
                FALLBACK_CONTENT=$(cat <<EOS
${FALLBACK_SHEBANG}awk -f /dev/stdin "\$@" <<'AWK_EOF'
${PRIMARY_SOLUTION_LOGIC}
AWK_EOF
EOS
)
                ;;
        esac

        echo -e "$FALLBACK_CONTENT" > "$FALLBACK_BASENAME"
        chmod +x "$FALLBACK_BASENAME"
    done

    # Run synchro eval
    synchro eval

    # Pop back to the original directory for the next iteration
    popd > /dev/null
done