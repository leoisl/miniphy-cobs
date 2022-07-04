from pathlib import Path
from PIL import Image
import numpy as np
import argparse
import shutil
import logging
import sys
import math
from scripts.decompress_and_check_image import are_COBS_indexes_identical

# avoids error:
# PIL.Image.DecompressionBombError: Image size (200000000 pixels) exceeds limit of 178956970 pixels, could be decompression bomb DOS attack.
# TODO: should we really avoid this error?
Image.MAX_IMAGE_PIXELS = None  # avoids

logging.basicConfig(stream=sys.stdout, level=logging.DEBUG, datefmt='%Y-%m-%d %H:%M:%S',
                    format='%(asctime)s %(levelname)-8s %(message)s')


def get_args():
    parser = argparse.ArgumentParser(description='Convert a binary object to a compressed image.',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--input', type=str, help='Binary object to be compressed', required=True)
    parser.add_argument('--output_dir', type=str, help='Where to save the diferent compressions', required=True)
    parser.add_argument('--width', type=int, default=4000, help='Width of the image (should equal nb of samples)')
    parser.add_argument('--number_of_rows_per_batch', type=int, default=50000,
                        help='Number of rows to have in each batch')
    args = parser.parse_args()
    return args


def compress_image(image, filename):
    logging.info(f"Compressing using PNG...")
    image.save(f"{filename}.png", 'PNG', optimize=True, bits=1)
    logging.info("Done!")


class DataNotAlignable(Exception):
    pass


def compress_bloom_filter_data(bf_data, width, filename):
    bf_data = np.frombuffer(bf_data, np.uint8)
    bf_data = np.unpackbits(bf_data)
    bf_data = bf_data.astype(bool)
    bf_data_size_before_padding = bf_data.size

    data_is_not_alignable = width % 8 != 0
    if data_is_not_alignable:
        raise DataNotAlignable("Error: width is not divisible by 8, data will not be aligned")

    height = math.ceil(bf_data.size / width)
    bf_data = np.pad(bf_data, (0, height*width - bf_data.size))
    bf_data = bf_data.reshape((height, width))

    logging.info(f"Bloom filter size before padding = {bf_data_size_before_padding}")
    logging.info(f"Bloom filter size after padding = {bf_data.size}")
    logging.info(f"Width = {width}")
    logging.info(f"Height = {height}")

    logging.info("Creating image from numpy matrix...")
    image = Image.fromarray(bf_data)

    compress_image(image, filename)

    return bf_data, image, height, bf_data_size_before_padding


def split_and_compress(image, width, height, number_of_rows_per_batch, filename):
    for index in range(0, math.ceil(height / number_of_rows_per_batch)):
        image_row_from = index * number_of_rows_per_batch
        image_row_to = min(image_row_from + number_of_rows_per_batch, height)
        logging.info(f"Cropping image: {(0, image_row_from, width, image_row_to)}")
        sub_image = image.crop((0, image_row_from, width, image_row_to))
        compress_image(sub_image, f"{filename}.part_{index}")


def create_transposed_bf_matrix(bf_data, transposed_bf_matrix_fh):
    transposed_bf_data = np.transpose(bf_data)
    transposed_bf_data = np.packbits(transposed_bf_data)
    transposed_bf_matrix_fh.write(transposed_bf_data.tobytes())


def compress(input_index, output, width, number_of_rows_per_batch):
    input_filename = input_index.name

    logging.info("Copying original index...")
    shutil.copy(str(input_index), output)

    logging.info("Reading binary object...")
    with open(input_index, "rb") as input_fh:
        data = input_fh.read()

    logging.info("Extracting and writing header...")
    first_classic_index_pos = data.index(b"CLASSIC_INDEX")
    second_classic_index_pos = data.index(b"CLASSIC_INDEX", first_classic_index_pos+1)
    bf_matrix_start_pos = second_classic_index_pos + len(b"CLASSIC_INDEX")
    cobs_header = data[:bf_matrix_start_pos]
    with open(output / f"{input_filename}.cobs_header.bin", "wb") as cobs_header_fh:
        cobs_header_fh.write(cobs_header)

    logging.info("Compressing bloom filter data...")
    bf_data = data[bf_matrix_start_pos:]
    bf_data, image, height, bf_data_size_before_padding = compress_bloom_filter_data(bf_data, width,
                                                                            str(output / f"{input_filename}.all"))

    logging.info("Writing metadata to uncompress COBS index")
    with open(output / f"{input_filename}.cobs_header.metadata", "w") as cobs_metadata_fh:
        print(f"BF_size = {bf_data_size_before_padding}", file=cobs_metadata_fh)


    logging.info("Writing transposed BF matrix")
    with open(output / f"{input_filename}.bf_matrix.transposed", "wb") as transposed_bf_matrix_fh:
        create_transposed_bf_matrix(bf_data, transposed_bf_matrix_fh)


    logging.info("Checking compression for correctness...")
    cobs_indexes_are_identical = are_COBS_indexes_identical(str(output / f"{input_filename}.all.png"),
                                                            str(output / f"{input_filename}.cobs_header.bin"),
                                                            str(output / f"{input_filename}.cobs_header.metadata"),
                                                            str(input_index))
    assert cobs_indexes_are_identical, "The COBS compressed index is corrupted"
    logging.info("The COBS compressed index is Ok!")

    split_and_compress(image, width, height, number_of_rows_per_batch, str(output / input_filename))


def main():
    args = get_args()
    input_index = Path(args.input)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=False)
    compress(input_index, output_dir, args.width, args.number_of_rows_per_batch)


if __name__ == "__main__":
    main()
