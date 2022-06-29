#!/bin/bash
set -e -x -o pipefail

main() {
    #Make directories to hold outputs
    mkdir /home/dnanexus/out
    mkdir /home/dnanexus/out/output_csv
    mkdir /home/dnanexus/out/output_features_csv

    if [ -z "$query_vcf" ]; then # when there's NO query file
        touch /home/dnanexus/out/output_csv/noQueryVcfFound.stats.csv
        touch /home/dnanexus/out/output_features_csv/noQueryVcfFound..features.csv

    else # when there IS a query vcf
        # Download inputs from DNAnexus in parallel, these will be downloaded to /home/dnanexus/in/
        dx-download-all-inputs --parallel

        # unzip reference file
        gunzip $reference_file_path
        reference_file_path=$(echo ${reference_file_path%.*})

        # Move all file paths to current directory
        find ~/in -type f -name "*" -print0 | xargs -0 -I {} mv {} ./

        reference_file=${reference_file_path##*/}
        truth_high_confidence_bed=${truth_high_confidence_bed_path##*/}
        panel_bed=${panel_bed_path##*/}
        truth_vcf=${truth_vcf_path##*/}
        query_vcf=${query_vcf_path##*/}
        pkrusche_happy_docker=${pkrusche_happy_docker_path##*/}

        prefix=$(basename $(basename ${query_vcf%%_*}))

        # set up docker to run sompy
        service docker start

        docker load -i $pkrusche_happy_docker
        pkrusche_happy_id=$(docker images --format="{{.ID}}")


        # Run sompy with truth VCF, query VCF with the referene genome.
        # Use the truth and capture panel bed to only calculate recall/precision
        # those regoins. For anything outside those regions, count as unknown
        # with the parameter --count-unk. Any variants that doesn't
        # have the filter "PASS" will still be assessed using the parameter
        # --include-nonpass. Add a feature table to breakdown that
        # variants that are tp,fp and fn with the parameter --feature-table generic.
        command="time docker run -v /home/dnanexus/:/data \
            $pkrusche_happy_id /opt/hap.py/bin/som.py \
            /data/$truth_vcf /data/$query_vcf \
            -r /data/$reference_file \
            -f /data/$truth_high_confidence_bed \
            -R /data/$panel_bed \
            --count-unk --include-nonpass --feature-table generic \
            -o data/"$prefix" "

        eval $command

        # Move outputs to correct directories for upload back to project
        cp "$prefix".stats.csv /home/dnanexus/out/output_csv/
        cp "$prefix".features.csv /home/dnanexus/out/output_features_csv/
    fi

    #Upload outputs (from /home/dnanexus/out) to DNAnexus
    dx-upload-all-outputs --parallel

}
