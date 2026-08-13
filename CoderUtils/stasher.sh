#!/bin/zsh

# ARG0="--store"          # src_root_dir    (can be empty)
# ARG1="--apply"          # dest_root_dir   (can be empty)
# ARG2="--list"           # no requested value

PATH_RECORD_ROOT_DIR="/home/coder/workspace/.peaks_records"
PATH_TARGET_ROOT_DIR="/home/coder/workspace/peaks" # default

# Fixed array syntax for zsh/bash
RECORD_LIST_PATH=(
    "SConstruct"
    "RunUnityTest_Coder.py"
    ".vscode/launch.json"
)

function IsExisted() {
    # return 
    #   0 : EXISTED
    #   1 : NON-EXISTED
    if [[ -e "$1" ]]; then
        return 0
    else
        return 1
    fi
}

function StoreFrom() {
    # Arg0 : Absolute path to store
    # return 
    #   0 : SUCCESS
    #   1 : ERROR SRC NOT FOUND
    #   2 : ERROR DEST NOT FOUND
    #   3 : UNKNOWN
    local src_root_dir="$1"
    
    # Check if source root directory exists
    IsExisted "$src_root_dir" || return 1
    
    # Create destination record root directory if it doesn't exist
    mkdir -p "$PATH_RECORD_ROOT_DIR"
    IsExisted "$PATH_RECORD_ROOT_DIR" || return 2

    local unknown_error=0

    for item in "${RECORD_LIST_PATH[@]}"; do
        local src_file="$src_root_dir/$item"
        local dest_file="$PATH_RECORD_ROOT_DIR/$item"
        
        if IsExisted "$src_file"; then
            echo "    '$src_file' -> '$dest_file'"
            # Create parent directory for the item in destination
            mkdir -p "$(dirname "$dest_file")"
            # Copy file/folder
            cp -r "$src_file" "$dest_file" || unknown_error=1
        fi
    done

    if [[ $unknown_error -eq 1 ]]; then
        return 3
    fi

    return 0
}

function ApplyTo() {
    # Arg0 : Absolute path to apply
    # return 
    #   0 : SUCCESS
    #   1 : ERROR SRC NOT FOUND
    #   2 : ERROR DEST NOT FOUND
    #   3 : UNKNOWN
    local dest_root_dir="$1"
    
    # Check if source record root directory exists
    IsExisted "$PATH_RECORD_ROOT_DIR" || return 1
    
    # Create destination root directory if it doesn't exist
    mkdir -p "$dest_root_dir"
    IsExisted "$dest_root_dir" || return 2

    local unknown_error=0

    for item in "${RECORD_LIST_PATH[@]}"; do
        local src_file="$PATH_RECORD_ROOT_DIR/$item"
        local dest_file="$dest_root_dir/$item"
        
        if IsExisted "$src_file"; then
            echo "    '$src_file' -> '$dest_file'"
            # Create parent directory for the item in destination
            mkdir -p "$(dirname "$dest_file")"
            # Copy file/folder
            cp -r "$src_file" "$dest_file" || unknown_error=1
        fi
    done

    if [[ $unknown_error -eq 1 ]]; then
        return 3
    fi

    return 0
}

# MAIN EXECUTION ##################################################################################
case "$1" in
    --store)
        # Sử dụng tham số $2 nếu có, nếu không thì dùng PATH_TARGET_ROOT_DIR
        local target_dir="${2:-$PATH_TARGET_ROOT_DIR}"
        echo "Storing from: $target_dir"
        StoreFrom "$target_dir"
        ret=$?
        echo "StoreFrom exited with code: $ret"
        exit $ret
        ;;
    --apply)
        # Sử dụng tham số $2 nếu có, nếu không thì dùng PATH_TARGET_ROOT_DIR
        local target_dir="${2:-$PATH_TARGET_ROOT_DIR}"
        echo "Applying to: $target_dir"
        ApplyTo "$target_dir"
        ret=$?
        echo "ApplyTo exited with code: $ret"
        exit $ret
        ;;
    --list)
        echo "Record List Paths:"
        for item in "${RECORD_LIST_PATH[@]}"; do
            echo "   '$item'"
        done
        exit 0
        ;;
    *)
        echo "Usage: $0 [--store [src_root_dir]] | [--apply [dest_root_dir]] | [--list]"
        echo "Note: If src_root_dir or dest_root_dir is omitted, it defaults to $PATH_TARGET_ROOT_DIR"
        exit 1
        ;;
esac
