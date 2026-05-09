#!/usr/bin/env bash

# This script is intended to be run in the *base directory* of the project under test.

# This script expects the following environment variables to be set (e.g. via the `.env` file):
# - AUDITHUB_ORGANIZATION_ID: The ID of the AuditHub organization to use
# - AUDITHUB_PROJECT_ID: The ID of the AuditHub project to use
# - AUDITHUB_BASE_URL: The base URL of the AuditHub instance (e.g. "https://app.audithub.com")
# - AUDITHUB_OIDC_CONFIGURATION_URL: The OIDC configuration URL for authenticating with AuditHub (e.g. "https://auth.audithub.com/.well-known/openid-configuration")
# - AUDITHUB_OIDC_CLIENT_ID: The OIDC client ID for authenticating with AuditHub (e.g. "my-audithub-client-id")
# - AUDITHUB_OIDC_CLIENT_SECRET: The OIDC client secret for authenticating with AuditHub (e.g. "my-audithub-client-secret")

set -e

# Assumes a `.env` file is present in the same directory as this script with the necessary environment variables
# defined. If not using such a file, comment this out and export necessary variables before invoking.
source .env

# Path to `ah` binary. May not be necessary if `ah` is already in the PATH.
AH="PATH_TO_AH_BINARY/ah" # e.g. "/home/user/.local/bin/ah"

#######################################################################################
# OrCa task configuration values (may change based on particular run/use case)
#######################################################################################

# NOTE: These paths are *relative* to the base directory of the project under test.
SPECS_PATH="specs"
HINTS_PATH="hints"
DEPLOYMENT_INFO_PATH="onchain.deployment.json" # Set to "null" if not using *on-chain* deployment mode.
AUXILIARY_DEPLOYMENT_SCRIPT_PATH="script/OrCa.s.sol" # Set to "null" if not using this feature.
FUZZ_TARGETS_PATH="orca-fuzzing-targets.json" # Format from AuditHub export. Set to "null" if not using.
FUZZ_BLACKLIST_PATH="orca-fuzzing-blacklist.json" # Format from AuditHub export. Set to "null" if not using.

# Fuzzing parameters: Update these as desired
TIMEOUT="1800" # Timeout in seconds for the OrCa task (1800s = 30min, comfortable first-run budget)
DETECT_REENTRANCY="false" # Whether to enable OrCa's reentrancy detection feature
FUZZ_PURE="false" # Whether to enable fuzzing of pure/view functions
FORK_NETWORK="mainnet" # Network to fork for fuzzing (e.g. "mainnet"). Leave empty to not fork.
FORK_BLOCK_NUMBER="null" # Block number to fork from. Set to "null" to fork from the latest block or if no forking selected.
LOG_LEVEL="DEBUG" # Log level for `ah` commands (e.g. "debug", "info", "warning", "error")

# These are exported because they are read by the `ah` command as environment variables
# Excluding OrCa artifacts, Foundry artifacts, git, vscode, and Mac related files and folders to run a clean project over AuditHub
export AUDITHUB_ZIP_EXCLUDED_DIRECTORIES='[".git",".github",".findings",".vscode","out","broadcast","cache","veridise_artifacts"]'
export AUDITHUB_ZIP_EXCLUDED_FILE_EXTENSIONS='["lcov.info","call_metrics.json",".DS_Store",".gitmodules",".gitignore",".env"]'

#######################################################################################
# Version creation and OrCa task execution (likely no changes needed below this point)
#######################################################################################

SOURCE_FOLDER=$PWD

echo "[upload-files]"

# Note: This uploads a new *version* to AuditHub on each new invocation of OrCa. This
#       is necessary to capture changes to source code, specs, hints, deployment scripts, etc.
#       If none of this setup changes, the version upload below can be commented out and replaced
#       with a single pre-prepared version ID corresponding to the desired setup.
version_id=$($AH create-version-via-local-archive --name "@$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --source-folder $SOURCE_FOLDER --log-level $LOG_LEVEL)
export AUDITHUB_VERSION_ID="$version_id"

echo "[collect-specs]"

SPECS=()

# We change directory to the directory with the specs as specs is a path
# *relative* to the source folder.
cd $SOURCE_FOLDER
if [[ -d "$SPECS_PATH" ]]; then
    # The `read`` command here reads in each file path from the `find`` command.
    # The `-r` flag tells it that backslackes are not escape characters.
    # The `-d` option sets the empty string as the terminating character for the input line.
    while IFS= read -r -d '' f; do
        SPECS+=("$f")
    # The `find`` command finds every file *recursively* with the extension `.spec`.
    # The `-print0` option is used for handling special characters in filenames
    # without treating them as delimiters.
    done < <(find $SPECS_PATH -type f -name '*.spec' -print0)
fi
cd $SOURCE_FOLDER # Return to original directory after collecting specs

if ((${#SPECS[@]} == 0)); then
  echo "ERROR: No specs found in folder ${SPECS_PATH}/ from folder ${SOURCE_FOLDER}" >&2
  exit 1
fi

echo "[collect-hints]"

HINTS=()

# We change directory to the directory with the specs as specs is a path
# *relative* to the source folder.
cd $SOURCE_FOLDER
if [[ -d "$HINTS_PATH" ]]; then
    # The `read`` command here reads in each file path from the `find`` command.
    # The `-r` flag tells it that backslackes are not escape characters.
    # The `-d` option sets the empty string as the terminating character for the input line.
    while IFS= read -r -d '' f; do
        HINTS+=("$f")
    # The `find`` command finds every file *recursively* with the extension `.spec`.
    # The `-print0` option is used for handling special characters in filenames
    # without treating them as delimiters.
    done < <(find "$HINTS_PATH" -type f -name '*.hint' -print0)
fi
cd $SOURCE_FOLDER

echo "[parse-fuzzing-blacklist-and-targets]"

expand_fuzz_list() {
    local input="$1"
    local kind="$2"
    local file_kind="$3"

    if [[ "$input" == "null" ]]; then
        return 0
    fi

    if [[ "$input" == *.json ]]; then
        if [[ ! -f "$input" ]]; then
            echo "ERROR: ${kind} JSON file not found: ${input}" >&2
            exit 1
        fi

        while IFS= read -r entry; do
            if [[ -n "$entry" ]]; then
                printf '%s\n' "$entry"
            fi
        done < <(
            if [[ "$file_kind" == "targets" ]]; then
                jq -r '.targets[]' "$input"
            else
                jq -r '.blacklist[] | "\(.contract).\(.function)"' "$input"
            fi
        )
        return 0
    fi

    for entry in $input; do
        printf '%s\n' "$entry"
    done
}

FUZZ_TARGET_ARGS=()
while IFS= read -r entry; do
    if [[ -n "$entry" ]]; then
        FUZZ_TARGET_ARGS+=("$entry")
    fi
done < <(expand_fuzz_list "$FUZZ_TARGETS_PATH" "fuzz targets" "targets")

FUZZ_BLACKLIST_ARGS=()
while IFS= read -r entry; do
    if [[ -n "$entry" ]]; then
        FUZZ_BLACKLIST_ARGS+=("$entry")
    fi
done < <(expand_fuzz_list "$FUZZ_BLACKLIST_PATH" "fuzz blacklist" "blacklist")

echo "Starting OrCa Task with VersionID: $version_id"
echo "[start-orca-task]"

START_TASK_COMMAND=("$AH" start-orca-task --log-level "$LOG_LEVEL" --embedded_specs "${SPECS[@]}" --name "api@$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --timeout "$TIMEOUT")
if [ "$DEPLOYMENT_INFO_PATH" != "null" ]; then
    START_TASK_COMMAND+=(--on-chain --deployment-info-file "$DEPLOYMENT_INFO_PATH")
fi
if [ "$AUXILIARY_DEPLOYMENT_SCRIPT_PATH" != "null" ]; then
    START_TASK_COMMAND+=(--auxiliary-deployment-script "$AUXILIARY_DEPLOYMENT_SCRIPT_PATH")
fi
if [ "$DETECT_REENTRANCY" == "true" ]; then
    START_TASK_COMMAND+=(--detect-reentrancy)
fi
if [ "$FUZZ_PURE" == "true" ]; then
    START_TASK_COMMAND+=(--fuzz_pure)
fi
if ((${#FUZZ_TARGET_ARGS[@]} != 0)); then
    START_TASK_COMMAND+=(--fuzz_targets "${FUZZ_TARGET_ARGS[@]}")
fi
if ((${#FUZZ_BLACKLIST_ARGS[@]} != 0)); then
    START_TASK_COMMAND+=(--fuzzing_blacklist "${FUZZ_BLACKLIST_ARGS[@]}")
fi
if [ "$FORK_NETWORK" != "" ]; then
    START_TASK_COMMAND+=(--fork_network "$FORK_NETWORK")
fi
if [ "$FORK_BLOCK_NUMBER" != "null" ]; then
    START_TASK_COMMAND+=(--fork_block_number "$FORK_BLOCK_NUMBER")
fi
if ((${#HINTS[@]} != 0)); then
    START_TASK_COMMAND+=(--embedded-hints "${HINTS[@]}")
fi
task_id=$("${START_TASK_COMMAND[@]}")

echo "TaskID:$task_id"

$AH monitor-task --task-id $task_id --log-level $LOG_LEVEL

echo "[fetch-artifacts]"

$AH download-artifact --task-id $task_id --step-code run-orca --name call_metrics.json --output-file $SOURCE_FOLDER/call_metrics.json --log-level $LOG_LEVEL

echo "OrCa complete!"
