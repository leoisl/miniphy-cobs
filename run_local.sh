#!/usr/bin/env bash
set -eux
snakemake --use-conda -j1 -- create_new_batches
snakemake --use-conda -j1
