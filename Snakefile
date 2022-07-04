from pathlib import Path
from glob import glob
import json
import random
import string
import os

configfile: "config.yaml"

# ======================================================
# Helper functions
# ======================================================
def find_all_files_recursively(dir, pattern):
    return (Path(file) for file in glob(f"{dir}/**/{pattern}", recursive=True))

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
        f"{config['output_dir']}/compressed_indexes/all.cobs_classic.xz.tar"


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
    random_names = get_n_random_sorted_names(len(order))
    for sample_name, random_name in zip(order, random_names):
        source = Path(sample_name_to_assembly_path[sample_name])
        source_suffixes = "".join(source.suffixes)
        dest = output_dir.resolve() / f"{random_name}_{sample_name}{source_suffixes}"
        os.symlink(str(source), str(dest))

rule reorder_genomes:
    input:
        order_file = lambda wildcards: get_order_name_to_order_path(get_all_ordering_files(config['ordering_dir']))[wildcards.order_name],
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


rule run_COBS:
    input:
        reordered_assembly_dir = rules.reorder_genomes.output.reordered_assemblies_dir
    output:
        COBS_out_dir = directory(f"{config['output_dir']}/COBS_out/{{order_name}}")
    threads: 8
    resources:
        mem_mb=lambda wildcards, attempt: attempt * 16000
    container:
        config["cobs_container"]
    log:
        "logs/run_COBS_{order_name}.log"
    shell:
        "cobs classic-construct -T {threads} {input.reordered_assembly_dir} " \
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
        mem_mb=lambda wildcards, attempt: attempt * 24000
    log:
        "logs/compress_COBS_index_{order_name}.log"
    shell:
        "xz -9 -T{threads} -e -k -c --lzma2=preset=9,dict=1500MiB,nice=250 {params.COBS_index} " \
        ">{output.COBS_compressed_index} 2>{log}"


rule combine_all_indexes:
    input:
        COBS_compressed_indexes = expand(f"{config['output_dir']}/compressed_indexes/{{order_name}}.cobs_classic.xz",
                                         order_name=get_order_name_to_order_path(get_all_ordering_files(config['ordering_dir'])))
    output:
        COBS_combined_compressed_index = f"{config['output_dir']}/compressed_indexes/all.cobs_classic.xz.tar"
    threads: 1
    resources:
        mem_mb=2000
    log:
        "logs/combine_all_indexes.log"
    shell:
        "tar -cvf {output.COBS_combined_compressed_index} {input.COBS_compressed_indexes} >{log} 2>&1"
