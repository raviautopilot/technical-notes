# JQ OPERATIONS & WRAPPER CHEATSHEET
**Version: 1.0 | Updated: 2026**

---

## 🚀 OVERVIEW

`jq-ops.sh` is a comprehensive wrapper script for `jq` designed to simplify everyday JSON parsing, inspection, and manipulation tasks. It addresses common pain points such as in-place editing, schema understanding, filtering arrays without writing complex `jq` filters, and auto-detecting data types (numbers, booleans, arrays, objects vs raw strings).

### 🛠️ Installation & Setup

Ensure `jq` is installed:
```bash
sudo apt install jq
```

Make `jq-ops.sh` executable:
```bash
chmod +x ./002_rsys/batch-scripts/sh/jq-ops.sh
```

---

## ⚙️ GLOBAL OPTIONS

These options can be specified anywhere on the command line to modify how `jq-ops.sh` handles input and output.

| Option | Long Option | Description |
|:---|:---|:---|
| | `--in-place` | Modify the input file directly (cannot be used with stdin). |
| `-o <file>` | `--output <file>` | Write the output to a specified file instead of stdout. |
| | `--color` | Force colorized output (enabled by default on TTY). |
| | `--no-color` | Disable colorized output (monochrome). |
| `-h` | `--help` | Display the help menu. |

---

## 📂 COMMANDS REFERENCE

### 1. `validate`
Check if the input JSON is well-formed.

* **Usage:** `jq-ops.sh validate [file]`
* **Stdin Support:** Yes (use `-` or omit file)
* **Examples:**
  ```bash
  jq-ops.sh validate config.json
  cat raw_payload.json | jq-ops.sh validate
  ```

---

### 2. `format`
Format, pretty-print, or minify JSON documents.

* **Usage:** `jq-ops.sh format [file] [options]`
* **Options:**
  * `-m`, `--minify` : Compact/minify JSON output to a single line.
  * `-t`, `--tabs` : Indent output using tab characters.
  * `-s N`, `--spaces N` : Indent output using `N` space characters (default: 2).
* **Examples:**
  ```bash
  # Pretty-print with 4 spaces in-place
  jq-ops.sh format config.json -s 4 --in-place

  # Minify JSON from stdin
  curl -s https://api.example.com/data | jq-ops.sh format --minify
  ```

---

### 3. `struct`
Analyze and inspect the schema or structure of a JSON document.

* **Usage:** `jq-ops.sh struct <subcommand> [file]`
* **Subcommands:**
  * `schema` *(default)*: Print paths and data types (collapsing array index items to `[]` for a generic schema).
  * `summary`: Print summary statistics (nesting depth, total keys, array length, etc.).
  * `keys`: Print top-level keys of the object (or element keys if the root is an array).
  * `paths`: Print all available paths in dot/bracket notation.
  * `leafs`: Print all paths leading to scalar leaf values.
* **Examples:**
  ```bash
  # Print the generic schema of a JSON file
  jq-ops.sh struct schema config.json

  # Get structural summary statistics
  jq-ops.sh struct summary countries.json
  ```

---

### 4. `search`
Search keys and values matching a query term or regular expression.

* **Usage:** `jq-ops.sh search [file] <term> [options]`
* **Options:**
  * `-k`, `--keys` : Search only within key names.
  * `-v`, `--values` : Search only within values.
  * `-i`, `--ignore-case` : Ignore case when searching.
* **Examples:**
  ```bash
  # Search both keys and values for "Turkey" case-insensitively
  jq-ops.sh search countries.json "Turkey" -i

  # Search only for keys matching "capital"
  jq-ops.sh search countries.json "capital" -k
  ```

---

### 5. `filter`
Apply a custom jq filter expression (wrapper for raw jq with in-place/output support).

* **Usage:** `jq-ops.sh filter [file] <expression>`
* **Examples:**
  ```bash
  # Extract names of all countries
  jq-ops.sh filter countries.json "map(.name)"
  ```

---

### 6. `select`
Select items from a list/array (or filters an object) based on a key condition.

* **Usage:** `jq-ops.sh select [file] <field> <operator> <value>`
* **Operators:** `==`, `!=`, `>`, `<`, `>=`, `<=`, `contains`, `test` (regex test)
* **Smart Parsing:** Checks if `<value>` is a number, boolean, array, or object, and processes it correctly.
* **Examples:**
  ```bash
  # Find countries where subregion equals "Western Asia"
  jq-ops.sh select countries.json subregion "==" "Western Asia"

  # Find countries where population is greater than 100,000,000
  jq-ops.sh select countries.json population ">" 100000000

  # Search for country names containing "united" (case-insensitive test)
  jq-ops.sh select countries.json name "test" "united"
  ```

---

### 7. `set`
Add or update a value at a specified JSON path.

* **Usage:** `jq-ops.sh set [file] <path> <value>`
* **Smart Parsing:** Auto-detects data types. If `<value>` is valid JSON (e.g. `true`, `123`, `null`, `[]`, `{"x":1}`), it is assigned as that type. Otherwise, it is assigned as a string.
* **Examples:**
  ```bash
  # Enable active status (boolean) in-place
  jq-ops.sh set config.json "users[0].active" true --in-place

  # Set a user's role (string) in-place
  jq-ops.sh set config.json "users[0].role" "admin" --in-place
  ```

---

### 8. `delete`
Delete a key or array index at a specified path.

* **Usage:** `jq-ops.sh delete [file] <path>`
* **Examples:**
  ```bash
  # Delete temporary token in-place
  jq-ops.sh delete config.json "users[0].temp_token" --in-place
  ```

---

### 9. `append`
Append a value to an array at a specified JSON path.

* **Usage:** `jq-ops.sh append [file] <path> <value>`
* **Smart Parsing:** Auto-detects data types. If `<value>` is valid JSON, it is parsed and appended. Otherwise, it is appended as a string.
* **Examples:**
  ```bash
  # Append a role (string) in-place
  jq-ops.sh append config.json "users[0].roles" "operator" --in-place

  # Append a new object to an array
  jq-ops.sh append config.json "events" '{"id": 1, "type": "click"}' --in-place
  ```

---

## 💡 PRACTICAL WORKFLOWS & RECIPES

### In-Place configuration updates
```bash
# 1. Update timeout value in config.json
./jq-ops.sh set config.json "settings.timeout" 30 --in-place

# 2. Append new tag to project array
./jq-ops.sh append config.json "project.tags" "dev" --in-place

# 3. Verify format and validate
./jq-ops.sh format config.json --in-place
```

### Inspecting Unknown JSON Structure
```bash
# Get quick summary statistics
./jq-ops.sh struct summary payload.json

# Check structural schema (nested types)
./jq-ops.sh struct schema payload.json

# Extract keys at the root
./jq-ops.sh struct keys payload.json
```

### Extracting Sub-datasets
```bash
# Select only European countries and write to a new file
./jq-ops.sh select countries.json region "==" "Europe" -o europe.json
```
