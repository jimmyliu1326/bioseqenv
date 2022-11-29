#!/usr/bin/env bash

usage() {
echo "
This shell script functions to batch process Sanger sequencing signal data (.ab1) in parallel. The script assembles the data using 
Tracy and offers both de novo or reference-guided assembly

BatchTracy.sh [options]

Example usage: BatchTracy.sh -i samples.csv -o /path/to/outdir

Required arguments:
-s|--sample          .csv file with first column as sample name and second column as path to ab1 data, no headers required
                    (for BioSeqDB, this becomes the sample name)
-i|--input         Path to input directory (for BioSeqDB, this becomes the complete input path)
-o|--output        Path to output directory

Optional arguments:
-r|--reference      Path to reference sequence used for reference-guided assembly
-p|--parallel       Number of samples to process in parallel (Default: 4). p=0 indicates BioSeqDB conventions for assemblers.
-m|--maxAb1         Maximum number of ab1 files (0 if all)
-h|--help           Display help message
"
}

# define global variables
script_name=$(basename $0 .sh)
PARALLEL_N=4
MAX_AB1=0

# parse arguments
opts=`getopt -o hs:i:o:p:m:r: -l help,sample:,input:,output:,parallel:,maxAb1:,reference: -- "$@"`
eval set -- "$opts"
if [ $? != 0 ] ; then echo "${script_name}: Invalid arguments used, exiting"; usage; exit 1 ; fi
if [[ $1 =~ ^--$ ]] ; then echo "${script_name}: Invalid arguments used, exiting"; usage; exit 1 ; fi

while true; do
    case "$1" in
        -s|--sample) SAMPLE=$2; shift 2;;
      	-i|--input) INPUT_PATH=$2; shift 2;;
        -o|--output) OUTPUT_PATH=$2; shift 2;;
        -r|--reference) REFERENCE_PATH=$2; shift 2;;
        -p|--parallel) PARALLEL_N=$2; shift 2;;
        -m|--maxAb1) MAX_AB1=$2; shift 2;;
        --) shift; break ;;
        -h|--help) usage; exit 0;;
    esac
done

# check if required arguments are given
if test -z $SAMPLE; then echo "${script_name}: Required argument -s is missing, exiting"; exit 1; fi
if test -z $INPUT_PATH; then echo "${script_name}: Required argument -i is missing, exiting"; exit 1; fi
if test -z $OUTPUT_PATH; then echo "${script_name}: Required argument -o is missing, exiting"; exit 1; fi

# check dependencies
tracy -h 2&>1 /dev/null
if [[ $? -ne 0 ]]; then echo "${script_name}: tracy cannot be called, check its installation"; exit 1; fi

# If p = 0, then use standard BioSeqDB convention for invoking assembler.
# Input is the sample name, output is the path to the sample. Actual output goes to staging.
if [[ $PARALLEL_N -eq 0 ]]; then
  echo Assembling $SAMPLE from $INPUT_PATH.

  # How many .ab1 files are in input path? Must be at least 1.

  fileCount=$( ls $INPUT_PATH/*.ab1 | wc -l )
  echo "*.ab1 file count=$fileCount."
  if [ $fileCount -lt 1 ]
  then 
    echo "$INPUT_PATH must have at least one .ab1 file."  
    exit 2
  fi

  # Remember where we are.
  currentDirectory="$PWD"

  # Define the directory where the work will be done.
  stagingDirectory="/c/data/staging/$INPUT_PATH"
  stagingDirectory="$OUTPUT_PATH"

  # If the stagingDirectory already exists, remove it before creating it again.
  #if [ -d $stagingDirectory ] 
  #then
  #  rm -rf $stagingDirectory
  #fi
  #mkdir $stagingDirectory
  cd $INPUT_PATH
  #combine all the individual files into one; NO! tracy requires individual trace files.
  if [[ $MAX_AB1 -eq 0 ]];
  then
    for file in *.ab1; do (cat "${file}";) > $stagingDirectory/${file}; done
  else
    count=$MAX_AB1

    for file in *.ab1; 
      do (cat "${file}";) >> $stagingDirectory/${file};
        let count=count-1; 
        echo "$count"; 
        if [ $count -lt 1 ];
        then
          break
        fi        
      done
  fi

  cd $stagingDirectory
  echo "Starting Tracy assembler run at: `date` reading file $SAMPLE.ab1."
  
  ## de novo assembly if reference not given
  if test -z $REFERENCE_PATH; then
    tracy assemble $stagingDirectory/*.ab1 -o $stagingDirectory/$SAMPLE 2>&1
  else
    # else reference-guided assembly
    # validate reference sequence path
    if ! test -f $REFERENCE_PATH; then echo "${script_name}: Specified reference sequence does not exist, exiting"; exit 1; fi
    tracy assemble $stagingDirectory/*.ab1 -o $stagingDirectory/$SAMPLE -r $REFERENCE_PATH 2>&1
  fi

  # print pipeline success if error-free
  if [[ $? -eq 0 ]]; then
    echo "${script_name}: Assembly run completed successfully! The consensus sequences are written to: $stagingDirectory"
  else
    echo "${script_name}: Assembly failed"
    exit 2
  fi
  exit 0
fi

# # Otherwise continue with non-BioSeqDB-type parallel processing.
# parallel -h 2&>1 /dev/null
# if [[ $? -ne 255 ]]; then echo "${script_name}: parallel cannot be called, check its installation"; exit 1; fi

# # validate input samples.csv
# if ! test -f $INPUT_PATH; then echo "${script_name}: Input sample file does not exist, exiting"; exit 1; fi

# while read lines; do
#   sample=$(echo $lines | cut -f1 -d',')
#   path=$(echo $lines | cut -f2 -d',')
#   # check if listed directory exists
#   if ! test -d $path; then
#     echo "${script_name}: ${sample} directory cannot be found, check its path listed in the input file, exiting"
#     exit 1
#   fi
#   # check if listed directory contains at least 1 .ab1 file
#   if [[ $(find $path -name '*.ab1' | wc -l) -eq 0 ]]; then
#     echo "${script_name}: ${sample} directory does not contain any .ab1 files, exiting"
#     exit 1
#   fi
# done < $INPUT_PATH

# # Batch Process
# ## de novo assembly if reference not given
# if test -z $REFERENCE_PATH; then
#   # run in parallel
#   parallel -j $PARALLEL_N 'sample=$(echo {1} | cut -f1 -d","); path=$(echo {1} | cut -f2 -d","); tracy assemble $path/*.ab1 -o ${2}/$sample/$sample' ::: $(cat $INPUT_PATH) ::: $(echo $OUTPUT_PATH)
# else
#   # else reference-guided assembly
#   # validate reference sequence path
#   if ! test -f $REFERENCE_PATH; then echo "${script_name}: Specified reference sequence does not exist, exiting"; exit 1; fi
#   # run in parallel
#   parallel -j $PARALLEL_N 'sample=$(echo {1} | cut -f1 -d","); path=$(echo {1} | cut -f2 -d","); tracy assemble $path/*.ab1 -o ${2}/$sample/$sample -r {3}' ::: $(cat $INPUT_PATH) ::: $(echo $OUTPUT_PATH) ::: $(echo $REFERENCE_PATH)
# fi

# # print pipeline success if error-free
# if [[ $? -eq 0 ]]; then
#   echo "${script_name}: Assembly run completed successfully! The consensus sequences are written to: $OUTPUT_PATH"
# fi
