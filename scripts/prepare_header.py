import glob
import sys
import os

pattern = sys.argv[1]
file_list = glob.glob(pattern)

with open(sys.argv[2], "w") as outfile:
    for file in file_list:
        outfile.write(f"#include \"{os.path.basename(file)}\"\n")
