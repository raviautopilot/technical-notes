#!/usr/bin/env bash
# jq-ops.sh - Comprehensive JSON operations and helper tool using jq
#
# This script wraps standard jq commands to make viewing, searching, 
# modifying, and structuring JSON files simple and intuitive.

set -euo pipefail

# Global variables
IN_PLACE=false
OUTPUT_FILE=""
FORCE_COLOR=false
DISABLE_COLOR=false
INPUT_FILE=""
TEMP_FILE=""

# Color codes (will be initialized in setup_colors)
RED=""
GREEN=""
YELLOW=""
BLUE=""
CYAN=""
NC=""

# Setup colors based on terminal detection or global options
setup_colors() {
    if [ "$DISABLE_COLOR" = true ]; then
        RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
    elif [ "$FORCE_COLOR" = true ] || [ -t 1 ]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
    fi
}

print_err() {
    echo -e "${RED}Error:${NC} $1" >&2
}

print_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

print_info() {
    echo -e "${CYAN}$1${NC}"
}

# Cleanup function to delete temporary files on exit
cleanup() {
    if [ -n "$TEMP_FILE" ] && [ -f "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE"
    fi
}
trap cleanup EXIT

# Resolve input file (handles stdin vs file)
resolve_input_file() {
    local input_arg="$1"
    if [ -z "$input_arg" ] || [ "$input_arg" = "-" ]; then
        # Check if stdin is a TTY (interactive)
        if [ -t 0 ]; then
            print_err "No input file specified and stdin is interactive."
            exit 1
        fi
        # Read from stdin to temp file
        TEMP_FILE=$(mktemp)
        cat > "$TEMP_FILE"
        INPUT_FILE="$TEMP_FILE"
    else
        if [ ! -f "$input_arg" ]; then
            print_err "File not found: $input_arg"
            exit 1
        fi
        INPUT_FILE="$input_arg"
    fi
}

# Handle stdout, output files, and in-place edits
handle_output() {
    local jq_expr="$1"
    
    if [ "$IN_PLACE" = true ]; then
        if [ "$INPUT_FILE" = "$TEMP_FILE" ]; then
            print_err "Cannot modify stdin in-place. Please specify an output file (-o) or redirect stdout."
            exit 1
        fi
        
        local out_temp
        out_temp=$(mktemp)
        
        # Run command
        if eval "$jq_expr < \"$INPUT_FILE\"" > "$out_temp"; then
            mv "$out_temp" "$INPUT_FILE"
            print_ok "File modified in-place: $INPUT_FILE"
        else
            rm -f "$out_temp"
            print_err "Operation failed. File was not modified."
            exit 1
        fi
    elif [ -n "$OUTPUT_FILE" ]; then
        if eval "$jq_expr < \"$INPUT_FILE\"" > "$OUTPUT_FILE"; then
            print_ok "Output written to: $OUTPUT_FILE"
        else
            print_err "Operation failed. Output not written."
            exit 1
        fi
    else
        # Just run to stdout (passing color options if TTY or forced)
        local color_flag=""
        if [ "$DISABLE_COLOR" = true ]; then
            color_flag=" -M" # jq monochrome
        elif [ "$FORCE_COLOR" = true ] || [ -t 1 ]; then
            color_flag=" -C" # jq color
        fi
        
        # Insert color flag into jq command (assuming jq is the first word)
        local run_expr
        run_expr=$(echo "$jq_expr" | sed "s/^jq/jq$color_flag/")
        eval "$run_expr < \"$INPUT_FILE\""
    fi
}

# Validate JSON content
validate_json() {
    if jq -e . >/dev/null 2>&1 < "$INPUT_FILE"; then
        print_ok "Valid JSON"
        return 0
    else
        local err_msg
        err_msg=$(jq -e . 2>&1 < "$INPUT_FILE" || true)
        print_err "Invalid JSON"
        echo "$err_msg" >&2
        return 1
    fi
}

cmd_validate() {
    local file_arg="${1:-}"
    resolve_input_file "$file_arg"
    validate_json
}

# Format and pretty-print JSON
cmd_format() {
    local minify=false
    local indent_char="spaces"
    local indent_size=2
    local input_file_arg=""
    
    # Parse format-specific options
    while [ $# -gt 0 ]; do
        case "$1" in
            -m|--minify)
                minify=true
                shift
                ;;
            -t|--tabs)
                indent_char="tabs"
                shift
                ;;
            -s|--spaces)
                indent_char="spaces"
                if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
                    indent_size="$2"
                    shift 2
                else
                    print_err "Option --spaces requires a numeric argument."
                    exit 1
                fi
                ;;
            *)
                if [ -z "$input_file_arg" ]; then
                    input_file_arg="$1"
                    shift
                else
                    print_err "Unknown argument: $1"
                    exit 1
                fi
                ;;
        esac
    done
    
    resolve_input_file "$input_file_arg"
    
    # Validate first
    if ! jq -e . >/dev/null 2>&1 < "$INPUT_FILE"; then
        print_err "Cannot format invalid JSON."
        validate_json >/dev/null || true
        exit 1
    fi
    
    # Construct jq command
    local jq_cmd="jq"
    if [ "$minify" = true ]; then
        jq_cmd="$jq_cmd -c"
    elif [ "$indent_char" = "tabs" ]; then
        jq_cmd="$jq_cmd --tab"
    else
        jq_cmd="$jq_cmd --indent $indent_size"
    fi
    jq_cmd="$jq_cmd '.'"
    
    handle_output "$jq_cmd"
}

# Analyze JSON structure
cmd_struct() {
    local subcmd="schema"
    local file_arg=""
    
    # Check if there are arguments
    if [ $# -eq 1 ]; then
        if [ -f "$1" ] || [ "$1" = "-" ]; then
            file_arg="$1"
        else
            subcmd="$1"
        fi
    elif [ $# -eq 2 ]; then
        subcmd="$1"
        file_arg="$2"
    fi
    
    resolve_input_file "$file_arg"
    
    # Validate first
    if ! jq -e . >/dev/null 2>&1 < "$INPUT_FILE"; then
        print_err "Cannot analyze structure of invalid JSON."
        validate_json >/dev/null || true
        exit 1
    fi
    
    case "$subcmd" in
        keys)
            jq -r 'if type == "object" then keys_unsorted[] elif type == "array" then "Root is an array. First element keys: " + (.[0] | if type == "object" then keys_unsorted | join(", ") else type end) else "Root is a scalar of type: " + type end' "$INPUT_FILE"
            ;;
        paths)
            jq -r 'def to_path_str: reduce .[] as $item (""; if ($item | type) == "number" then . + "[" + ($item | tostring) + "]" else if . == "" then $item else . + "." + $item end end); paths | to_path_str' "$INPUT_FILE"
            ;;
        leafs)
            jq -r 'def to_path_str: reduce .[] as $item (""; if ($item | type) == "number" then . + "[" + ($item | tostring) + "]" else if . == "" then $item else . + "." + $item end end); paths(scalars) | to_path_str' "$INPUT_FILE"
            ;;
        schema)
            jq -r '
              def to_schema_path: reduce .[] as $item (""; if ($item | type) == "number" then . + "[]" else if . == "" then $item else . + "." + $item end end);
              [paths as $p | {path: ($p | to_schema_path), type: (getpath($p) | type)}] | unique_by(.path) | .[] | "\(.path) : \(.type)"
            ' "$INPUT_FILE"
            ;;
        summary)
            local size_bytes=$(wc -c < "$INPUT_FILE")
            local stats
            stats=$(jq -r '
              [paths | length] as $depths |
              {
                type: type,
                depth: ($depths | max // 0),
                keys_count: (if type == "object" then keys | length elif type == "array" then length else 0 end),
                total_nodes: ([paths] | length),
                leaf_nodes: ([paths(scalars)] | length)
              } | "\(.type)|\(.depth)|\(.keys_count)|\(.total_nodes)|\(.leaf_nodes)"
            ' "$INPUT_FILE")
            
            IFS='|' read -r r_type r_depth r_keys r_total r_leafs <<< "$stats"
            
            echo -e "${CYAN}========================================${NC}"
            echo -e "${BLUE}JSON Structure Summary${NC}"
            echo -e "${CYAN}========================================${NC}"
            echo -e "File Path:     ${YELLOW}$INPUT_FILE${NC}"
            echo -e "File Size:     ${YELLOW}$size_bytes${NC} bytes"
            echo -e "Root Type:     ${YELLOW}$r_type${NC}"
            echo -e "Nesting Depth: ${YELLOW}$r_depth${NC}"
            if [ "$r_type" = "array" ]; then
                echo -e "Array Length:  ${YELLOW}$r_keys${NC}"
            elif [ "$r_type" = "object" ]; then
                echo -e "Root Keys:     ${YELLOW}$r_keys${NC}"
            fi
            echo -e "Total Paths:   ${YELLOW}$r_total${NC}"
            echo -e "Leaf Nodes:    ${YELLOW}$r_leafs${NC}"
            echo -e "${CYAN}========================================${NC}"
            ;;
        *)
            print_err "Unknown struct subcommand: $subcmd"
            echo "Available struct subcommands: keys, paths, leafs, schema, summary"
            exit 1
            ;;
    esac
}

# Search keys and values matching pattern
cmd_search() {
    local search_keys=true
    local search_values=true
    local ignore_case=false
    local term=""
    local file_arg=""
    
    # Parse options and arguments
    local pos_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -k|--keys)
                search_keys=true
                search_values=false
                shift
                ;;
            -v|--values)
                search_keys=false
                search_values=true
                shift
                ;;
            -i|--ignore-case)
                ignore_case=true
                shift
                ;;
            -kv|-vk)
                search_keys=true
                search_values=true
                shift
                ;;
            -*)
                print_err "Unknown option: $1"
                exit 1
                ;;
            *)
                pos_args+=("$1")
                shift
                ;;
        esac
    done
    
    if [ ${#pos_args[@]} -eq 1 ]; then
        term="${pos_args[0]}"
        file_arg="-"
    elif [ ${#pos_args[@]} -eq 2 ]; then
        file_arg="${pos_args[0]}"
        term="${pos_args[1]}"
    else
        print_err "Invalid arguments for search. Usage: search [file] <term> [options]"
        exit 1
    fi
    
    resolve_input_file "$file_arg"
    
    if [ -z "$term" ]; then
        print_err "Search term cannot be empty."
        exit 1
    fi
    
    # Validate first
    if ! jq -e . >/dev/null 2>&1 < "$INPUT_FILE"; then
        print_err "Cannot search in invalid JSON."
        validate_json >/dev/null || true
        exit 1
    fi
    
    local flags=""
    if [ "$ignore_case" = true ]; then
        flags="i"
    fi
    
    # Construct jq script
    local jq_script=""
    jq_script='
      def to_path_str: reduce .[] as $item (""; if ($item | type) == "number" then . + "[" + ($item | tostring) + "]" else if . == "" then $item else . + "." + $item end end);
    '
    
    if [ "$search_keys" = true ] && [ "$search_values" = true ]; then
        jq_script="$jq_script"'
          (paths as $p | select($p[-1] | tostring | test($term; $flags)) | {type: "Key Match", path: ($p | to_path_str), val: getpath($p)}),
          (paths(scalars) as $p | select(getpath($p) | tostring | test($term; $flags)) | {type: "Value Match", path: ($p | to_path_str), val: getpath($p)})
        '
    elif [ "$search_keys" = true ]; then
        jq_script="$jq_script"'
          paths as $p | select($p[-1] | tostring | test($term; $flags)) | {type: "Key Match", path: ($p | to_path_str), val: getpath($p)}
        '
    else
        jq_script="$jq_script"'
          paths(scalars) as $p | select(getpath($p) | tostring | test($term; $flags)) | {type: "Value Match", path: ($p | to_path_str), val: getpath($p)}
        '
    fi
    
    jq_script="$jq_script"' | "\(.type)|\(.path)|\(.val | tostring)"'
    
    # Execute
    local results
    results=$(jq -r --arg term "$term" --arg flags "$flags" "$jq_script" "$INPUT_FILE" 2>/dev/null || true)
    
    if [ -z "$results" ]; then
        print_info "No matches found for term '$term'."
        return 0
    fi
    
    echo -e "${CYAN}Search results for term '${YELLOW}$term${CYAN}':${NC}"
    echo "----------------------------------------"
    while IFS='|' read -r match_type path val; do
        if [ "$match_type" = "Key Match" ]; then
            echo -e "[${GREEN}Key${NC}]   ${BLUE}$path${NC} = ${NC}$val"
        else
            echo -e "[${YELLOW}Value${NC}] ${BLUE}$path${NC} = ${NC}$val"
        fi
    done <<< "$results"
    echo "----------------------------------------"
}

# Run a custom jq filter
cmd_filter() {
    local file_arg=""
    local expr=""
    
    local pos_args=()
    while [ $# -gt 0 ]; do
        pos_args+=("$1")
        shift
    done
    
    if [ ${#pos_args[@]} -eq 1 ]; then
        expr="${pos_args[0]}"
        file_arg="-"
    elif [ ${#pos_args[@]} -eq 2 ]; then
        file_arg="${pos_args[0]}"
        expr="${pos_args[1]}"
    else
        print_err "Invalid arguments for filter. Usage: filter [file] <expression>"
        exit 1
    fi
    
    resolve_input_file "$file_arg"
    
    if [ -z "$expr" ]; then
        print_err "Filter expression cannot be empty."
        exit 1
    fi
    
    # Validate first
    if ! jq -e . >/dev/null 2>&1 < "$INPUT_FILE"; then
        print_err "Cannot filter invalid JSON."
        validate_json >/dev/null || true
        exit 1
    fi
    
    local jq_cmd="jq '$expr'"
    handle_output "$jq_cmd"
}

# Select elements matching field condition
cmd_select() {
    local file_arg=""
    local field=""
    local op=""
    local val=""
    
    local pos_args=()
    while [ $# -gt 0 ]; do
        pos_args+=("$1")
        shift
    done
    
    if [ ${#pos_args[@]} -eq 3 ]; then
        field="${pos_args[0]}"
        op="${pos_args[1]}"
        val="${pos_args[2]}"
        file_arg="-"
    elif [ ${#pos_args[@]} -eq 4 ]; then
        file_arg="${pos_args[0]}"
        field="${pos_args[1]}"
        op="${pos_args[2]}"
        val="${pos_args[3]}"
    else
        print_err "Invalid arguments for select. Usage: select [file] <field> <operator> <value>"
        echo "Supported operators: ==, !=, >, <, >=, <=, contains, test"
        exit 1
    fi
    
    resolve_input_file "$file_arg"
    
    case "$op" in
        "=="|"!="|">"|"<"|">="|"<="|contains|test)
            ;;
        *)
            print_err "Unsupported operator: $op"
            echo "Supported operators: ==, !=, >, <, >=, <=, contains, test"
            exit 1
            ;;
    esac
    
    local field_expr="$field"
    if [[ ! "$field_expr" =~ ^\. ]]; then
        field_expr=".$field_expr"
    fi
    
    local arg_flag="--arg"
    if jq -e . >/dev/null 2>&1 <<< "$val"; then
        arg_flag="--argjson"
    fi
    
    local cond=""
    if [ "$op" = "contains" ]; then
        cond="$field_expr | contains(\$val)"
    elif [ "$op" = "test" ]; then
        cond="$field_expr | tostring | test(\$val; \"i\")"
    else
        cond="$field_expr $op \$val"
    fi
    
    local jq_filter="if type == \"array\" then map(select($cond)) else select($cond) end"
    local jq_cmd="jq $arg_flag val '$(echo "$val" | sed "s/'/'\\\\''/g")' '$jq_filter'"
    handle_output "$jq_cmd"
}

# Add or update value at specified path
cmd_set() {
    local file_arg=""
    local path=""
    local val=""
    
    local pos_args=()
    while [ $# -gt 0 ]; do
        pos_args+=("$1")
        shift
    done
    
    if [ ${#pos_args[@]} -eq 2 ]; then
        path="${pos_args[0]}"
        val="${pos_args[1]}"
        file_arg="-"
    elif [ ${#pos_args[@]} -eq 3 ]; then
        file_arg="${pos_args[0]}"
        path="${pos_args[1]}"
        val="${pos_args[2]}"
    else
        print_err "Invalid arguments for set. Usage: set [file] <path> <value>"
        exit 1
    fi
    
    resolve_input_file "$file_arg"
    
    local path_expr="$path"
    if [[ ! "$path_expr" =~ ^\. ]]; then
        path_expr=".$path_expr"
    fi
    
    local arg_flag="--arg"
    if jq -e . >/dev/null 2>&1 <<< "$val"; then
        arg_flag="--argjson"
    fi
    
    local jq_filter="$path_expr = \$val"
    local jq_cmd="jq $arg_flag val '$(echo "$val" | sed "s/'/'\\\\''/g")' '$jq_filter'"
    handle_output "$jq_cmd"
}

# Delete key or array index at path
cmd_delete() {
    local file_arg=""
    local path=""
    
    local pos_args=()
    while [ $# -gt 0 ]; do
        pos_args+=("$1")
        shift
    done
    
    if [ ${#pos_args[@]} -eq 1 ]; then
        path="${pos_args[0]}"
        file_arg="-"
    elif [ ${#pos_args[@]} -eq 2 ]; then
        file_arg="${pos_args[0]}"
        path="${pos_args[1]}"
    else
        print_err "Invalid arguments for delete. Usage: delete [file] <path>"
        exit 1
    fi
    
    resolve_input_file "$file_arg"
    
    local path_expr="$path"
    if [[ ! "$path_expr" =~ ^\. ]]; then
        path_expr=".$path_expr"
    fi
    
    local jq_filter="del($path_expr)"
    local jq_cmd="jq '$jq_filter'"
    handle_output "$jq_cmd"
}

# Append value to array at path
cmd_append() {
    local file_arg=""
    local path=""
    local val=""
    
    local pos_args=()
    while [ $# -gt 0 ]; do
        pos_args+=("$1")
        shift
    done
    
    if [ ${#pos_args[@]} -eq 2 ]; then
        path="${pos_args[0]}"
        val="${pos_args[1]}"
        file_arg="-"
    elif [ ${#pos_args[@]} -eq 3 ]; then
        file_arg="${pos_args[0]}"
        path="${pos_args[1]}"
        val="${pos_args[2]}"
    else
        print_err "Invalid arguments for append. Usage: append [file] <path> <value>"
        exit 1
    fi
    
    resolve_input_file "$file_arg"
    
    local path_expr="$path"
    if [[ ! "$path_expr" =~ ^\. ]]; then
        path_expr=".$path_expr"
    fi
    
    local arg_flag="--arg"
    if jq -e . >/dev/null 2>&1 <<< "$val"; then
        arg_flag="--argjson"
    fi
    
    local jq_filter="$path_expr += [\$val]"
    local jq_cmd="jq $arg_flag val '$(echo "$val" | sed "s/'/'\\\\''/g")' '$jq_filter'"
    handle_output "$jq_cmd"
}

# Show help menu
show_help() {
    setup_colors
    cat << EOF
${CYAN}jq-ops.sh - Comprehensive JSON Operations Wrapper for jq${NC}

${BLUE}Usage:${NC} $0 [global-options] <command> [file-or-stdin] [arguments...]

${BLUE}Global Options:${NC}
  --in-place           Modify the input file in-place (cannot be used with stdin)
  -o, --output FILE    Write output to specified file instead of stdout
  --color              Force color output (default: auto-detect TTY)
  --no-color           Disable color output
  -h, --help           Show this help menu

${BLUE}Commands:${NC}
  validate             Validate if the file/stdin contains valid JSON
                       Usage: $0 validate [file]

  format               Format and pretty-print JSON
                       Usage: $0 format [file] [options]
                       Options:
                         -m, --minify    Compact/minify JSON output
                         -t, --tabs      Indent using tabs
                         -s, --spaces N  Indent using N spaces (default: 2)

  struct               Analyze structure/schema of JSON
                       Usage: $0 struct [keys|paths|leafs|schema|summary] [file]
                       Default subcommand is 'schema'.

  search               Search keys and values matching pattern (regex supported)
                       Usage: $0 search [file] <term> [options]
                       Options:
                         -k, --keys         Search only in key names
                         -v, --values       Search only in values
                         -i, --ignore-case  Ignore case when matching

  filter               Apply custom jq filter expression
                       Usage: $0 filter [file] <expression>

  select               Select elements matching field condition (for arrays/objects)
                       Usage: $0 select [file] <field> <operator> <value>
                       Operators: ==, !=, >, <, >=, <=, contains, test

  set                  Add or update a value at specified JSON path
                       Usage: $0 set [file] <path> <value>

  delete               Delete key/index at specified JSON path
                       Usage: $0 delete [file] <path>

  append               Append value to array at specified JSON path
                       Usage: $0 append [file] <path> <value>

${BLUE}Examples:${NC}
  # Format in-place with 4-space indentation
  $0 format data.json -s 4 --in-place

  # Search values matching 'admin' ignoring case
  $0 search data.json admin -v -i

  # Find all users with age > 25
  $0 select data.json users[].age ">" 25

  # Set active status to true for first user in-place
  $0 set data.json "users[0].active" true --in-place

  # Pipeline formatting
  cat data.json | $0 format --minify
EOF
}

# --- Main Logic ---

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    # We do a bootstrap setup colors since colors might not be initialized
    DISABLE_COLOR=false
    FORCE_COLOR=true
    setup_colors
    print_err "jq is not installed on this system. Please install it (e.g. 'sudo apt install jq') first."
    exit 1
fi

# Parse global options first, regardless of their position
cmd_args=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --in-place)
            IN_PLACE=true
            ;;
        -o|--output)
            next_idx=$((i + 1))
            if [ $next_idx -le $# ]; then
                OUTPUT_FILE="${!next_idx}"
                i=$next_idx
            else
                echo -e "\033[0;31mError:\033[0m Option -o/--output requires an argument." >&2
                exit 1
            fi
            ;;
        --color)
            FORCE_COLOR=true
            DISABLE_COLOR=false
            ;;
        --no-color)
            DISABLE_COLOR=true
            FORCE_COLOR=false
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            cmd_args+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

# Initialize colors
setup_colors

if [ ${#cmd_args[@]} -eq 0 ]; then
    show_help
    exit 0
fi

subcommand="${cmd_args[0]}"
subcommand_args=("${cmd_args[@]:1}")

case "$subcommand" in
    validate)
        cmd_validate "${subcommand_args[@]:-}"
        ;;
    format)
        cmd_format "${subcommand_args[@]:-}"
        ;;
    struct)
        cmd_struct "${subcommand_args[@]:-}"
        ;;
    search)
        cmd_search "${subcommand_args[@]:-}"
        ;;
    filter)
        cmd_filter "${subcommand_args[@]:-}"
        ;;
    select)
        cmd_select "${subcommand_args[@]:-}"
        ;;
    set)
        cmd_set "${subcommand_args[@]:-}"
        ;;
    delete)
        cmd_delete "${subcommand_args[@]:-}"
        ;;
    append)
        cmd_append "${subcommand_args[@]:-}"
        ;;
    help)
        show_help
        ;;
    *)
        print_err "Unknown subcommand: '$subcommand'"
        show_help
        exit 1
        ;;
esac
