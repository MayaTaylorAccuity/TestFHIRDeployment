#!/bin/bash

# Check if the main_folder parameter is provided
if [ -z "$1" ]; then
  echo "Error: Main folder parameter not provided."
  exit 1
fi

# Set the name of the main folder where you want to move the files
main_folder="$1"

# Loop through all subfolders in the current directory
for subfolder in /home/accuityGHR/Migrations/*; do

  # Get the folder name without the trailing slash
  folder_name=${subfolder##*/}

  # Set a counter variable for numbering the files
  count=1

  # Loop through all files in the subfolder
  for file in "$subfolder"/*; do

    # Get the file name without the path
    file_name=${file##*/}

    # Construct the new file name with the folder name prefix and numbering
    new_file_name="V${folder_name}_$(printf "%03d" $count)__${file_name}"

    # Move the file to the main folder with the new name
    mv "$file" "${main_folder}/${new_file_name}"

    # Increment the counter
    count=$((count+1))

    # Convert the file to utf-8 with LF line endings
    iconv -f iso-8859-1 -t utf-8 "${main_folder}/${new_file_name}" | tr -d '\r' > "${main_folder}/${new_file_name}.utf8"
    mv "${main_folder}/${new_file_name}.utf8" "${main_folder}/${new_file_name}"
  done
done
