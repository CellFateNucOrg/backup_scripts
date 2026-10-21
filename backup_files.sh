#!/bin/bash
#SBATCH --job-name=backup
#SBATCH --output=logs/%x_%j.out
#SBATCH --time=0-12:00:00
#SBATCH --cpus-per-task=32
#SBATCH --mem 32GB

#### Config ####

# Specify here how you want your folders to be archived. The archives will be saved in your user folder on the capacity storage.
# What each field means is explained below. The script can set some of those fields automatically based on file names. This is explained in the last section.

# input_dirs: directories to back up, separated by LINE or SPACE.
# exclude_folders: subfolders you don't want to archive, separated by LINE or SPACE.
# created: Creation date in ISO format. For example: created=20260910.
# initials: Your initials.
# strain: Strain number. For example: strain=1234.
# platform: What platform you used. For example: platform=lipsi.
# type: What type of data you acquired. For example, for spinning disk: type=sd.
# stage: Developmental stage. Options are: e (embryo), l1, l2, l3, l4, a (adult), d (dauer), and x (mixed). For example: stage=e.
# detail: Any additional info you want to add, SEPARATED BY UNDERSCORES. For example: detail=rnai_control.
# transfer: whether to move the archived folders onto the back-up server (true or false).
# account: Your campus account (needed to transfer the files onto the back-up server).
# user: Name of your user folder on the back-up server.

# Extracting file info automatically:
# You can use the fields 'created', 'strain', 'platform', 'type', 'stage', and 'detail' to extract the info that should be added to the archive's name from one of your files.
# To do so, assign the field a string starting with an @, followed by one or more comma-separated numbers. The numbers correspond to which parts of your file name (using _ as a separator) should be extracted.
# For example: if your file is named 20260101_1234_l1_rnai.tif, then created=@1 would extract the date 20260101, and stage=@3 would extract the stage l1.

# Input
input_dirs=(
)
exclude_folders=(dw)

# File info
created=@1
initials=db
strain=@2
platform=lipsi
type=sd
stage=@3
detail=@4

# Capacity storage
transfer=true
account=db23u401
user=dario

#### Script ####

# Make an array for created the archives
archives=()

extract_string() {
    # Extract fields from an '_'-separated file name ($1) based on an input string ($2) starting with '@', followed by comma-separated numbers that correspond to the file name's fields
    # For example, file name 'this_is_a_file_name' & string '@1,2,3' would return 'this_is_a'
    # If $2 does not start with '@', it is returned unchanged
    
    # Get args
    local file_name="$1"
    local input="$2"

    # If input starts with '@'
    if [[ "${input}" = @* ]]; then

        # ...split it by comma & save the numbers in an array
        IFS=',' read -a positions <<< "${input#@}"

        # Build a string with the fields of of the file name corresponding to the numbers in 'positions'
        string=""
        for pos in ${positions}; do
            add_string=$(echo ${file_name,,} | cut -d '_' -f $pos)
            string="${string}_${add_string}" 
            string="${string#_}"
        done

        # Return the string
        echo "$string"

    # If input does not start with '@', return it
    elif [ -n "${input}" ]; then
        echo "$input"
    
    # If input is empty, return "na"
    else
        echo "na"
    fi
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

    # Get first file name
    files=(${dir}/*)
    file_name=$(basename ${files[0]})

    # Get strings & build archive name
    set_created=$(extract_string "$file_name" "$created")
    set_strain=$(extract_string "$file_name" "$strain" )
    set_platform=$(extract_string "$file_name" "$platform" )
    set_type=$(extract_string  "$file_name" "$type")
    set_stage=$(extract_string "$file_name" "$stage" )
    set_detail=$(extract_string "$file_name" "$detail")
    archive_name="${set_created}_${initials}_${set_platform}_${set_type}_${set_stage}_${set_detail}"

    # Compress folder(s) and add their path(s) to 'archives'
    # -T0: use all available CPUs
    # -6: compression level (1-9, default 6)
    # -v -v: double verbose (show files being compressed & progress)
    if tar "${exclude_args[@]}" --use-compress-program="xz -T0 -6 -v -v" -cf "${archive_name}.tar.xz" "$folder"; then
        archives+=("${parent}/${archive_name}.tar.xz")
    fi
done

# # Quit if 'archives' is empty
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