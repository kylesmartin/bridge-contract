#!/bin/sh

rm -rf logs/storage/*

dirOutputs=$(ls out | grep '^[^.]*\.sol$') # assuming the out dir is at 'out'

while IFS= read -r contractDir; do
  innerDirOutputs=$(ls out/$contractDir)

  # Skip if folder ends with .s.sol
  if [[ $contractDir == *".s.sol" ]]; then
    continue
  fi

  while IFS= read -r jsonFile; do
    fileIn=out/$contractDir/$jsonFile
    fileOut=logs/storage/$contractDir:${jsonFile%.json}.log
    node .husky/storage-logger.js $fileIn $fileOut &
  done <<< "$innerDirOutputs"
done <<< "$dirOutputs"

# Wait for all background jobs to finish
wait