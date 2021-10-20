#!/bin/bash

###########################################################
# Search and download xeno canto records using their API: #
# https://www.xeno-canto.org/explore/api                  #
###########################################################

API_SEARCH_BASE_URL="https://www.xeno-canto.org/api/2/recordings?query="
SCRIPT_FILES_PREFIX="xenoscript"
SCRIPT_PATH="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 || exit; pwd -P)"
CURRENT_TIMESTAMP=$(date +%s)
SEARCH_RESULTS_FILENAME="${SCRIPT_FILES_PREFIX}_search_results_$CURRENT_TIMESTAMP.json"
export TEMPORARY_FOLDER='/tmp'
export FILENAMES_FILE="${SCRIPT_FILES_PREFIX}_filenames.log"
RESULTS_FILE=${TEMPORARY_FOLDER}/${SEARCH_RESULTS_FILENAME}
CURL_BIN=$(command -v curl)
JQ_BIN=$(command -v jq)
WGET_BIN=$(command -v wget)
PARALLEL_BIN=$(command -v parallel)

function validate_binary() {
  if [ -z "$2" ]; then
    echo "$1 binary not found, install or add it to the user system PATH"
    exit 1;
  fi
}

function validate_binaries() {
  validate_binary "curl" "$CURL_BIN"
  validate_binary "jq" "$JQ_BIN"
  validate_binary "wget" "$WGET_BIN"
  validate_binary "parallel" "$PARALLEL_BIN"
}

function print_usage() {
  echo -e "Usage: \n  $0 -q \"Dendrocopos leucotos\" -d -s 1000000

  -q            query pattern, PATTERNS are strings
  -d            download the search result
  -s            file size limit, SIZE in bytes
  -h            display this help and exit
  "
  exit 1
}

function validate_minimum_params() {
  if [ -z "$1" ]; then
    print_usage
  fi
}

function validate_only_integers() {
  if [[ ! "$1" =~ ^[0-9]+$ ]]; then
    print_usage
  fi
}

function parse_query() {
  QUERY=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr " " "+" | sed 's/ //g')
}

function xeno_canto_api_search() {
  echo -e "\nSearching results for $QUERY ..."
  parse_query "$QUERY"
  generate_results_file
  generate_summary_content
  print_summary
  if [ "$DOWNLOAD" == "true" ]; then
    download_confirmation
  fi
}

function download_files() {
  FILE_TYPE="mp3"
  EXTENDED_NAME="-"
  if [ "$SIZE" ]; then
    EXTENDED_NAME="${EXTENDED_NAME}size:${SIZE}-"
  fi
  DOWNLOAD_FOLDER="$(echo "$QUERY" | sed s/+/-/g)${EXTENDED_NAME}downloads-$(date +%s)"
  mkdir "$SCRIPT_PATH/$DOWNLOAD_FOLDER"
  touch "${TEMPORARY_FOLDER}/${FILENAMES_FILE}"
  URL_LIST=$(echo "$1" | sed 's/\"//g' | sed 's/\/\//https:\/\//g' | sed 's/ /\n/g')
  echo -e "\nComputing download list"
  echo "$URL_LIST" | "$PARALLEL_BIN" -n 1 -P 8 --bar compute_filename_column "{}"
  URL_LIST="$(cat ${TEMPORARY_FOLDER}/${FILENAMES_FILE})"
  echo -e "\nDownloading files"
  echo "$URL_LIST" | "$PARALLEL_BIN" -n 1 -P 8 --colsep " " --bar "$WGET_BIN" -q -O "$SCRIPT_PATH/$DOWNLOAD_FOLDER/{2}"-"$QUERY"."$FILE_TYPE" "{1}"
  TOTAL_FILES_DOWNLOADED=$(find "$SCRIPT_PATH/$DOWNLOAD_FOLDER" -type f | wc -l)
  echo -e "\nA total of $TOTAL_FILES_DOWNLOADED records have been downloaded at $SCRIPT_PATH/$DOWNLOAD_FOLDER"
  clean_the_house
}

function compute_filename_column() {
  prefix="$(echo "$1" | awk -F "/" '{print $4}')"
  echo "$1 $prefix" >> "${TEMPORARY_FOLDER}/${FILENAMES_FILE}"
}
export -f compute_filename_column

function generate_results_file() {
  $CURL_BIN -s "$API_SEARCH_BASE_URL$QUERY" | $JQ_BIN > "$RESULTS_FILE"
}

function generate_summary_content() {
  NUM_RECORDINGS=$(grep numRecordings "$RESULTS_FILE" | cut -d ":" -f2 | sed 's/,//' | sed 's/ //g' | sed 's/"//g')
  if [ "$NUM_RECORDINGS" -le 0 ]; then
    echo "No records found"
    exit 0
  fi
  NUM_SPECIES=$(grep numSpecies "$RESULTS_FILE" | cut -d ":" -f2 | sed 's/,//' | sed 's/ //g' | sed 's/"//g')
  PAGES=$(grep numPages "$RESULTS_FILE" | cut -d ":" -f2 | sed 's/,//' | sed 's/ //g')
}

function filter_download_list_by_size() {
  URL_LIST=$(echo "$1" | sed 's/\"//g' | sed 's/\/\//https:\/\//g' | sed 's/ /\n/g')
  echo -e "\nFiltering urls by size limit"
  export FILTER_FILE="${SCRIPT_FILES_PREFIX}_filter.log"
  touch "${TEMPORARY_FOLDER}/${FILTER_FILE}"
  echo "$URL_LIST" | $PARALLEL_BIN -n 1 -P 8 --bar add_file_if_size_is_under_limit
  TOTAL_URLS_FILTERED=$(wc -l < ${TEMPORARY_FOLDER}/${FILTER_FILE})  
  if [ "$TOTAL_URLS_FILTERED" -eq 0 ]; then
    echo -e "\nThere aren't any records smaller than $SIZE bytes"
    exit 0
  fi
  DOWNLOAD_URLS=$(sed 's/https://g' < ${TEMPORARY_FOLDER}/${FILTER_FILE})
}

function add_file_if_size_is_under_limit() {
  FILE_SIZE="$(curl -sIL  "$1" | awk '/Content-Length/{print $2}' | sed 's/ /\n/g' | tr -cd '[:alnum:]._-' )"
  if [ -n "$SIZE" ] && [ -n "$FILE_SIZE" ] && [ "$SIZE" -gt "$FILE_SIZE" ]; then
      echo "$1" >> "${TEMPORARY_FOLDER}/${FILTER_FILE}"
  fi
}
export -f add_file_if_size_is_under_limit

function generate_downloads_list() {
  DOWNLOAD_URLS="$($JQ_BIN '.recordings[] | .file' < "$RESULTS_FILE")"

  if [ "$PAGES" -gt 1 ] && [ "$DOWNLOAD" == "true" ]; then
    page_iterator=2
    while [ "$page_iterator" -le "$PAGES" ]; do
      $CURL_BIN -s "$API_SEARCH_BASE_URL$QUERY&page=$page_iterator" | $JQ_BIN > "$RESULTS_FILE$page_iterator"
      CURRENT_PAGE_DOWNLOAD_URLS="$($JQ_BIN '.recordings[] | .file' < "$RESULTS_FILE$page_iterator")"
      DOWNLOAD_URLS=$(echo -e "$DOWNLOAD_URLS\n$CURRENT_PAGE_DOWNLOAD_URLS")
      (("page_iterator+=1"))
    done
  fi

  if [ "$SIZE" ]; then
    export SIZE=$SIZE
    validate_only_integers "$SIZE"
    filter_download_list_by_size "$DOWNLOAD_URLS"
  fi
  DOWNLOAD_LIST_FILE="${SCRIPT_FILES_PREFIX}_downloads_urls.log"
  echo "$DOWNLOAD_URLS" > "${TEMPORARY_FOLDER}/${DOWNLOAD_LIST_FILE}"
}

function download_confirmation() {
  if [ "$SIZE" ]; then
    echo ""
    echo "Only files smaller than $SIZE bytes ($(bc <<< "scale=6; $SIZE/1000000") MB) will be downloaded"
  fi
  read -r -p "Are you sure to download? " yn
  case $yn in
    [Yy]* ) generate_downloads_list && download_files "$DOWNLOAD_URLS" ;;
    [Nn]* ) exit 0;;
    * ) echo "Please answer yes or no.";;
  esac
}

function print_summary() {
  echo ""
  echo "######################################"
  echo "       search results summary         "
  echo "######################################"
  echo "Number of recordings: $NUM_RECORDINGS"
  echo "Number of species: $NUM_SPECIES"
  echo "Pages: $PAGES"
  echo ""
}

function clean_the_house() {
  rm "${TEMPORARY_FOLDER}/${SCRIPT_FILES_PREFIX}"*
}

validate_binaries

while getopts 'q:ds:h' flag; do
  case "${flag}" in
    q) QUERY="${OPTARG}" ;;
    d) DOWNLOAD=true ;;
    s) SIZE="${OPTARG}" ;;
    h) fn_print_usage ;;
    *) fn_print_usage ;;
  esac
done

validate_minimum_params "$1"
xeno_canto_api_search
