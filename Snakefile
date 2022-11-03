from pathlib import Path
from glob import glob
import json
import random
import string
import os
import hashlib

configfile: "config.yaml"

# ======================================================
# Helper functions
# ======================================================
def find_all_files_recursively(dir, pattern):
    return [Path(file) for file in glob(f"{dir}/**/{pattern}", recursive=True)]

def get_all_ordering_files(ordering_dir):
    return find_all_files_recursively(ordering_dir, "*.txt")

def get_order_name_to_order_path(all_ordering_files):
    return {
        ordering_file.with_suffix("").name: Path(ordering_file).resolve()
        for ordering_file in all_ordering_files
    }

def get_all_assemblies_files(assemblies_dir):
    return find_all_files_recursively(assemblies_dir, "*.contigs.fa.gz")

def get_sample_name_to_assembly_path(all_assemblies_files):
    return {
        assembly_file.name.replace(".contigs.fa.gz", ""): str(assembly_file.resolve())
        for assembly_file in all_assemblies_files
    }

def get_order(filepath):
    with open(filepath) as order_fh:
        order = [line.strip() for line in order_fh.readlines()]
    return order

def get_random_name(length=40):
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for _ in range(length))

def get_n_random_sorted_names(n):
    random_names = set()
    while len(random_names) < n:
        random_names.add(get_random_name())
    return sorted(list(random_names))
# ======================================================
# Helper functions
# ======================================================

# ======================================================
# Rules and functions of rules
# ======================================================
rule all:
    input:
        f"{config['output_dir']}/compressed_indexes/all.cobs_classic.xz.tar",
        expand(f"{config['output_dir']}/asms_out/{{order_name}}.tar.xz",
        order_name=get_order_name_to_order_path(get_all_ordering_files(config["output_dir"] + "/new_batches")))


rule create_new_batches:
    input:
        config["output_dir"] + "/new_batches"


rule rebatch:
    input:
        all_ordering_files = get_all_ordering_files(config["ordering_dir"])
    output:
        new_batches_dir = directory(config["output_dir"] + "/new_batches")
    threads: 1
    resources:
        mem_mb=1000
    params:
        batch_size = config["batch_size"]
    run:
        import re
        from collections import defaultdict

        new_batches_dir = Path(output.new_batches_dir)
        new_batches_dir.mkdir()

        species_to_original_batch_paths = defaultdict(list)
        for ordering_file in input.all_ordering_files:
            ordering_file = Path(ordering_file)
            species = re.findall("(.+)__\d\d\.txt", ordering_file.name)[0]
            species_to_original_batch_paths[species].append(ordering_file)

        for species, original_batch_paths in species_to_original_batch_paths.items():
            original_batch_paths_parent = original_batch_paths[0].parent
            original_batch_paths_template = str(original_batch_paths_parent / species)
            genome_list = []
            for batch_number in range(1, len(original_batch_paths)+1):
                batch_path = original_batch_paths_template + f'__{batch_number:02d}.txt'
                genomes_in_batch = list(filter(lambda line: line.strip() != "",
                    Path(batch_path).read_text().split("\n")))
                genome_list.extend(genomes_in_batch)

            file_index = 1
            for start_index in range(0, len(genome_list), params.batch_size):
                genomes_to_output = genome_list[start_index : start_index+params.batch_size]
                new_batch_path = new_batches_dir / f"{species}__{file_index:05d}.txt"
                new_batch_path.write_text("\n".join(genomes_to_output)+"\n")
                file_index += 1


rule build_sample_name_to_assembly_path:
    input:
        assemblies_dir = config['assemblies_dir']
    output:
        sample_name_to_assembly_path_json = f"{config['output_dir']}/sample_name_to_assembly_path.json"
    threads: 1
    resources:
        mem_mb=2000
    log:
        "logs/build_sample_name_to_assembly_path.log"
    run:
        all_assembly_files = get_all_assemblies_files(input.assemblies_dir)
        sample_name_to_assembly_path = get_sample_name_to_assembly_path(all_assembly_files)
        with open(output.sample_name_to_assembly_path_json, 'w') as json_fh:
            json.dump(sample_name_to_assembly_path, json_fh)


def reorder_genomes(sample_name_to_assembly_path, order, output_dir):
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=False)
    order_as_str = "".join(order).encode("utf-8")
    sha1_hex = hashlib.sha1(order_as_str).hexdigest()
    sha1_hex_as_int = int(sha1_hex, 16)
    random.seed(sha1_hex_as_int)
    random_names = get_n_random_sorted_names(len(order))
    for sample_name, random_name in zip(order, random_names):
        source = Path(sample_name_to_assembly_path[sample_name])
        source_suffixes = "".join(source.suffixes)
        dest = output_dir.resolve() / f"{random_name}_{sample_name}{source_suffixes}"
        os.symlink(str(source), str(dest))


rule reorder_genomes:
    input:
        order_file = lambda wildcards: get_order_name_to_order_path(get_all_ordering_files(config["output_dir"] + "/new_batches"))[wildcards.order_name],
        sample_name_to_assembly_path_json = rules.build_sample_name_to_assembly_path.output.sample_name_to_assembly_path_json
    output:
        reordered_assemblies_dir = directory(f"{config['output_dir']}/reordered_assemblies/{{order_name}}")
    threads: 1
    resources:
        mem_mb=2000
    log:
        "logs/reorder_genomes_{order_name}.log"
    run:
        with open(input.sample_name_to_assembly_path_json) as json_fh:
            sample_name_to_assembly_path = json.load(json_fh)
        order = get_order(input.order_file)
        reorder_genomes(sample_name_to_assembly_path, order, output.reordered_assemblies_dir)


rule rebatch_assemblies:
    input:
        reordered_assembly_dir = rules.reorder_genomes.output.reordered_assemblies_dir
    output:
        compressed_assembly = f"{config['output_dir']}/asms_out/{{order_name}}.tar.xz"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: attempt * 1000
    params:
        tar_file = lambda wildcards: f"{config['output_dir']}/asms_out/{wildcards.order_name}.tar",
        temp_dir = lambda wildcards: f"{config['output_dir']}/asms_out/{wildcards.order_name}/temp"
    shell:
        """
        mkdir -p {params.temp_dir}

        for compressed_assembly in {input.reordered_assembly_dir}/*.contigs.fa.gz
        do
            compressed_assembly=$(readlink -f $compressed_assembly)
            assembly=${{compressed_assembly::-3}}
            gunzip $compressed_assembly --keep --force --stdout > $assembly
            mv $assembly {params.temp_dir}
        done
        
        tar -cf {params.tar_file} {params.temp_dir}
        xz -9 -T1 -e -k -c --lzma2=preset=9,dict=64MiB,nice=250 {params.tar_file} > {output.compressed_assembly}
        
        rm -v {params.tar_file}
        rm -rfv {params.temp_dir}
        """


rule run_COBS:
    input:
        reordered_assembly_dir = rules.reorder_genomes.output.reordered_assemblies_dir
    output:
        COBS_out_dir = directory(f"{config['output_dir']}/COBS_out/{{order_name}}")
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: attempt * 4000
    log:
        "logs/run_COBS_{order_name}.log"
    conda: "envs/cobs.yaml"
    shell:
        "cobs classic-construct -T {threads} {input.reordered_assembly_dir} "
        "{output.COBS_out_dir}/{wildcards.order_name}.cobs_classic >{log} 2>&1"


rule compress_COBS_index:
    input:
        COBS_out_dir = f"{config['output_dir']}/COBS_out/{{order_name}}"
    output:
        COBS_compressed_index = f"{config['output_dir']}/compressed_indexes/{{order_name}}.cobs_classic.xz"
    params:
        COBS_index = lambda wildcards: f"{config['output_dir']}/COBS_out/{wildcards.order_name}/{wildcards.order_name}.cobs_classic"
    threads: 1
    resources:
        mem_mb=lambda wildcards, attempt: attempt * 4000
    log:
        "logs/compress_COBS_index_{order_name}.log"
    shell:
        "xz -9 -T{threads} -e -k -c --lzma2=preset=9,dict=64MiB,nice=250 {params.COBS_index} " \
        ">{output.COBS_compressed_index} 2>{log}"


rule combine_all_indexes:
    input:
        COBS_compressed_indexes = expand(f"{config['output_dir']}/compressed_indexes/{{order_name}}.cobs_classic.xz",
                                         order_name=get_order_name_to_order_path(get_all_ordering_files(config["output_dir"] + "/new_batches")))
    output:
        COBS_combined_compressed_index = f"{config['output_dir']}/compressed_indexes/all.cobs_classic.xz.tar"
    threads: 1
    resources:
        mem_mb=2000
    log:
        "logs/combine_all_indexes.log"
    shell:
        "tar -cvf {output.COBS_combined_compressed_index} {input.COBS_compressed_indexes} >{log} 2>&1"
