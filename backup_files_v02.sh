#!/bin/bash
#SBATCH --job-name=backup
#SBATCH --output=logs/%x_%j.out
#SBATCH --time=0-12:00:00
#SBATCH --cpus-per-task=32
#SBATCH --mem 32GB

#### Config ####

# Specify here how you want your folders to be archived. The created archives are saved in your user folder, named based on the fields specified below.
# The parameters you have to set are separated in to three groups:

# 1. USER INFO:
# account: Your campus account
# initials: Your initials
# user: Name of your user folder on the back-up server

# 2. INPUT:
# input_dirs: directories to back up, separated by LINE or SPACE
# exclude_folders: subfolders you don't want to archive, separated by LINE or SPACE
# transfer: whether to move the archived folders onto the back-up server (true or false)

# 3. FILE INFO:
# For each field, you can either specify the info yourself (OPTION A) or have the script extract the info for you (OPTION B). You can decide this for each field individually.
# For each field that is not specified at all, the string 'na' is instead added to the file name.

# OPTION A:
# Set any of the following fields:
# created: Creation date in ISO format. For example: created=20260910
# strain: Strain number. For example: strain=1234
# platform: What platform you used. For example: platform=lipsi
# type: What type of data you acquired. For example, for spinning disk: type=sd 
# stage: Developmental stage. Options are: e (embryo), l1, l2, l3, l4, a (adult), d (dauer), and x (mixed). For example: stage=e
# detail: Any additional info you want to add, SEPARATED BY UNDERSCORES. For example: detail=rnai_control

# OPTION B:
# You instead specify the field(s) with the '_from' suffix. For example: created_from=()
# The first argument (inside the parentheses) must be 'folder' or 'file', to extract the info from either the folder name a file (the first one) inside the folder.
# The second argument must be a number, specifying which substring to extract (substring means which part of the folder or file name when treating underscore as a delimiter).
# Example: you're backing up the folder /Volumes/meister.data/user/imaging/20260910_l1 which contains such as 1234_l1_001.nd2, 1234_l1_002.nd2, etc.
# If you specify the field: created_from=(folder 1), the extracted info (for the creation date) will be 20260910.
# If you specify the field: stage_from=(file 2), the extracted info (for stage) will be l1.

# USER INFO
account=db23u401
initials=db
user=dario

# INPUT
input_dirs=(
/Volumes/meister.data/dario/imaging/test_archive/1268/20260808_l1
)
exclude_folders=(dw)
transfer=true

# FILE INFO, OPTION A:
created=
strain=
platform=lipsi
type=sd
stage=
detail=

# FILE INFO, OPTION B:
created_from=(file 1)
strain_from=(file 2)
platform_from=()
type_from=()
stage_from=(file 3)
detail_from=(file 4)

#### Script ####

# Make an array for created the archives
archives=()

# Extract info from folder or file names (function)
extract_info() {
    # Get arguments
    local folder="$1"
    local test_var="$2"
    shift 2 # Discard $1 & $2 (to parse the third argument as an array)
    local test_arr=("$@")

    # Return $2 if it is non-zero (in lowercase)
    if [ -n "$test_var" ]; then
        substring="${test_var,,}"
    
    # Else check if $3 is an array with at least two items
    elif [ ${#test_arr[@]} -ge 2 ]; then
        # Decide whether to extract from folder or file name and what part to extract
        extract_from="${test_arr[0]}"
        substring_pos=("${test_arr[@]:1}")

        # Get the namer of the folder...
        if [ "$extract_from" = "folder" ]; then
            string=$folder
        # ...or the first file inside it
        elif [ "$extract_from" = "file" ]; then
            # Get the first filename
            files=(${dir}/*)
            string=$(basename ${files[0]})
        fi

        # Return substring (in lowercase)
        for pos in "${substring_pos[@]}"; do
            add_string=$(echo ${string,,} | cut -d '_' -f $pos)
            substring="${substring}_${add_string}"
        done

    # Return 'na' if info has not been specified & cannot be extracted
    else
        substring="na"
    fi

    # Return substring (& remove leading underscores)
    echo "${substring#_}"  
}

for i in "${!input_dirs[@]}"; do
    dir="${input_dirs[i]/Volumes/mnt}"

    # Split path into parent dir & folder folder
    parent=$(dirname $dir)
    folder=$(basename $dir)

    # cd to parent folder or exit
    cd $parent || exit 1

    # Make an array with the folders not to back up (relative to .)
    exclude_args=()
    for f in "${exclude_folders[@]}"; do
        exclude_args+=("--exclude=$folder/$f")
    done

    # Get substrings & build archive name
    set_created=$(extract_info "$folder" "$created" "${created_from[@]}")
    set_strain=$(extract_info "$folder" "$strain" "${strain_from[@]}")
    set_platform=$(extract_info "$folder" "$platform" "${platform_from[@]}")
    set_type=$(extract_info "$folder" "$type" "${type_from[@]}")
    set_stage=$(extract_info "$folder" "$stage" "${stage_from[@]}")
    set_detail=$(extract_info "$folder" "$detail" "${detail_from[@]}")
    archive_name="${set_created}_${initials}_${set_platform}_${set_type}_${set_stage}_${set_detail}"

    # Build archive name without adding 'na' when 'set_detail' has length zero
    # archive_name="${set_created}_${initials}_${set_platform}_${set_type}_${set_stage}"
    # if [ -n "${set_detail}" ] && [ "${set_detail}" != "na" ]; then
    #     archive_name="${archive_name}_${set_detail}"
    # fi

    # Compress folder(s) and add their path(s) to 'archives'
    # -T0: use all available CPUs
    # -6: compression level (1-9, default 6)
    # -v -v: double verbose (show files being compressed & progress)
    if tar "${exclude_args[@]}" --use-compress-program="xz -T0 -6 -v -v" -cf "${archive_name}.tar.xz" "$folder"; then
        archives+=("${parent}/${archive_name}.tar.xz")
    fi
done

# Quit if 'archives' is empty
if [ "${#archives[@]}" -eq 0 ]; then
    echo "Did not receive any folders to archive."
    exit 1
fi

echo "Created archives."

# Transfer (copy & paste) the created archives
# -a: archive mode (preserves permissions, timestamps, etc.)
# -v: verbose (show what is being transferred)
# -P: combines --partial (keep incomplete transfers in case something breaks) & --progress (show progress)
if [ "${transfer,,}" = "true" ]; then
    
    if rsync -avP "${archives[@]}" "${account}@submit01.unibe.ch:/storage/capacity/izb_meister/microscopy/${user}/"; then
        rm -f "${archives[@]}" # Delete the archives after copying
        echo "Transferred archives."
    else
        echo "Transfer failed."
        exit 1
    fi
fi
