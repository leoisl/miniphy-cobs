# mof-cobs-build

Creates and compresses ordered [COBS](https://github.com/iqbal-lab-org/cobs) indexes to later be used by
[mof-search][1].

# Dependencies

* `python 3.7+`;
* `snakemake`;
* `xz`;
* `tar`;

# Running

## Input

Just configure the four entries in [config.yaml](config.yaml):
* `ordering_dir`: a directory containing batches (text files) of ordered samples (one per line),
see [sample_data/ordering](sample_data/ordering) for one example;
* `assemblies_dir`: a directory containing assemblies. This directory can be subdivided in batches.
See [sample_data/assemblies](sample_data/assemblies) for one example;
* `output_dir`: the output dir;
* `cobs_executable_path`: the `COBS` executable path.

## Running

There are premade scripts to run locally or on a `LSF` cluster:

### Running locally

```
bash run_local.sh
```

### Running on a LSF cluster

Please have the [LSF profile](https://github.com/Snakemake-Profiles/lsf) installed and run:

```
bash run_local.sh
```

## Output

The main output is in `<output_dir>/compressed_indexes`. There you can find the `xz`-compressed `COBS` indexes, one
per batch, and also all of them in the single `tar` file `all.cobs_classic.xz.tar`.

## Running on the sample example

Just run locally:

```
bash run_local.sh
```

and take a look at the output files in `sample_data/out`.

## Creating compressed `COBS` indexes for the 661k high quality genomes

These were the indexes we used in the paper's [mof-search][1], and you can reproduce them as described below. If you
just want the indexes, you can download them from [TODO: add Zenodo link](zenodo) or just run `make download` in
[mof-search][1] root.

1. Decompress the 661k high quality ordering (the 661k full ordering is also available [here](661k_orderings/661k_phylogenetically_ordered.tar.xz)).
You can also create your own ordering):
```
cd 661k_orderings && tar -xvf 661k_phylogenetically_ordered_high_quality.tar.xz
```

2. Download the original 661k assemblies:

```
wget http://ftp.ebi.ac.uk/pub/databases/ENA2018-bacteria-661k/661_assemblies.tar
tar -xvf 661_assemblies.tar
```

3. Edit `config.yaml` to point to these directories:
```
ordering_dir: 661k_orderings/661k_phylogenetically_ordered_high_quality
assemblies_dir: 661_assemblies
```
Don't forget to configure your output dir and `COBS` executable.

[1]: https://github.com/karel-brinda/mof-search
