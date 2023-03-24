import argparse
from pathlib import Path
import shutil


def get_args():
    parser = argparse.ArgumentParser(
        description='Goes through an assembly dir and remove samples that are not high quality.')
    parser.add_argument('--high_quality', type=str, help='Path to a file with high quality genomes', required=True)
    parser.add_argument('--assemblies_dir', type=str, help='Path to a dir with all the assemblies (contains batches dirs inside)', required=True)
    parser.add_argument('--output_dir', type=str, help='Path to a dir with the updated orderings', required=True)
    args = parser.parse_args()
    return args


def main():
    args = get_args()

    with open(args.high_quality) as high_quality_fh:
        high_quality_genomes = set([line.strip() for line in high_quality_fh])

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for batch_dir in Path(args.assemblies_dir).iterdir():
        output_batch_dir = output_dir/batch_dir.name
        output_batch_dir.mkdir(parents=True, exist_ok=True)
        for file in batch_dir.iterdir():
            if file.name.endswith(".contigs.fa.gz"):
                sample = file.name.replace(".contigs.fa.gz", "")
                if sample in high_quality_genomes:
                    print(f"cp {file.resolve()} {output_batch_dir}")
                    shutil.copy(file.resolve(), output_batch_dir)


if __name__ == "__main__":
    main()
