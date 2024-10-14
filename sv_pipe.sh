#!/bin/bash

#SBATCH --job-name=sv_pipeline_mosaic
#SBATCH --time=05:00:00
#SBATCH --account=marth-rw
#SBATCH --partition=marth-shared-rw

# Output in my directory in the scratch space
#SBATCH -o /scratch/ucgd/lustre-labs/marth/scratch/u1069837/slurm-%j.out-%N
#SBATCH -e /scratch/ucgd/lustre-labs/marth/scratch/u1069837/slurm-%j.err-%N

# We need at least 4 cpus because smoove will try to use 4 threads by default
#SBATCH --ntasks=4
#SBATCH --mem=16G
#SBATCH --mail-type=ALL

# This is just my email change to appropriate email
#SBATCH --mail-user=emerson.lebleu@genetics.utah.edu

#Inputs to the script
PBDCRAM=$1
MOMCRAM=$2
DADCRAM=$3
O_SMOOVE_VCF=$4
REF_FASTA=$5

DOCTORED_MANTA_OUTPUT="doctor_manta.vcf.gz"
DUPHOLD_MANTA_OUTPUT="duphold_manta.vcf.gz"
SVAF_SMOOVE_OUTPUT="svaf_smoove.vcf"
SVAF_MANTA_OUTPUT="svaf_manta.vcf"

# set up scratch directory
SCRDIR=/scratch/ucgd/lustre-labs/marth/scratch/$USER/$SLURM_JOB_ID
mkdir -p $SCRDIR
# copy the scripts and reference files to the scratch dir
cp \
    run_manta_trio.sh \
    doctor_manta.py \
    ./smoove/bp_smoove.sif \
    sv_pipe.yml \
    SVAFotate_core_SV_popAFs.GRCh38.v4.1.bed.gz \
    $SCRDIR

cd $SCRDIR

# run the the manta script run_manta_trio.sh (needs the trio's urls CRAM format) -> new joint called vcf
./run_manta_trio.sh $PBDCRAM $MOMCRAM $DADCRAM 

# load the miniconda3 module will be needed for the doctor_manta.py and for the svafotate run at the end
module load \
    miniconda3/23.11.0 \
    singularity/4.1.1

# Check if the environment already exists, if not create it from the yml
ENV_NAME="sv_pipe_conda_env"
if conda info --envs | grep -q "$ENV_NAME"; then
    conda activate "$ENV_NAME"
else
    conda env create -f sv_pipe.yml
    conda activate "$ENV_NAME"
    
    conda install --file https://raw.githubusercontent.com/fakedrtom/SVAFotate/master/requirements.txt
    pip install git+https://github.com/fakedrtom/SVAFotate.git
fi

# the script is going to put a simlink to the manta vcf at ./diploidSV.vcf.gz
# modify the vcf with his doctor_manta.py script (needs input vcf, and output) -> new doc_vcf
python doctor_manta.py diploidSV.vcf.gz $DOCTORED_MANTA_OUTPUT

# TODO: run smoove duphold on the manta vcf -> dhanno_manta_vcf CONFIRM THAT THIS IS OKAY WITH TOM DOCS ARE NOT CLEAR ON EXPECTATIONS
singularity exec bp_smoove.sif duphold -v $DOCTORED_MANTA_OUTPUT -b $PBDCRAM $MOMCRAM $DADCRAM -f $REF_FASTA -o $DUPHOLD_MANTA_OUTPUT

#Run svafotate on both files (.8 ol threshold) -> filtered svaf_vcf
svafotate annotate -v $DUPHOLD_MANTA_OUTPUT -b SVAFotate_core_SV_popAFs.GRCh38.v4.1.bed.gz -o $SVAF_MANTA_OUTPUT -f 0.8 --cpu 4
bgzip $SVAF_MANTA_OUTPUT

svafotate annotate -v $O_SMOOVE_VCF -b SVAFotate_core_SV_popAFs.GRCh38.v4.1.bed.gz -o $SVAF_SMOOVE_OUTPUT -f 0.8 --cpu 4
bgzip $SVAF_SMOOVE_OUTPUT

conda deactivate "$ENV_NAME"

# Cleanup
rm run_manta_trio.sh \
    doctor_manta.py \
    rm bp_smoove.sif \
    sv_pipe.yml \
    SVAFotate_core_SV_popAFs.GRCh38.v4.1.bed.gz 
