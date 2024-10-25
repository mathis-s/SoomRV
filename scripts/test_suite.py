import os
import colorama
from colorama import Fore
from colorama import Style
import sys

colorama.init()

test_dir = "riscv-tests/isa"
if len(sys.argv) > 1: test_dir = sys.argv[1]

arr = os.popen(f"find {test_dir} -type f ! -size 0 -exec grep -IL . \"{{}}\" \\;").read().split('\n')

print(arr)

# we're running without a runtime, so no misaligned accesses.
arr.remove(f"{test_dir}/rv32ui-p-ma_data")
arr.remove(f"{test_dir}/rv32ui-v-ma_data")

categories = ["rv32ui", "rv32uc", "rv32si", "rv32mi"]

binary = "./obj_dir/VTop"

for category in categories:
    tests = [test for test in arr if test.find(category) != -1]
    for test in tests:
        print(f"running {test}:", end='')
        result = os.popen(f"{binary} -t {test}").read()

        if result.startswith("PASSED"):
            print(f" {Fore.GREEN}passed{Style.RESET_ALL}")
        else:
            print(f" {Fore.RED}failed{Style.RESET_ALL}:")
            print(os.popen(f"{binary} -x 0 -t {test} |& tail -n32").read())
            print("\n")
