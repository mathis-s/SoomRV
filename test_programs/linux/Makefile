BUILDROOT_DIR ?= buildroot
BUILDROOT_CFG ?= buildroot.config
KERNEL_CFG ?= kernel.config
BUSYBOX_CFG ?= busybox.config
RV32_OBJCOPY ?= riscv32-unknown-linux-gnu-objcopy

.PHONY: all
all: linux_image.elf

$(BUILDROOT_DIR): $(BUILDROOT_CFG) $(KERNEL_CFG) $(BUSYBOX_CFG)
	curl -Lo buildroot.tar.gz https://github.com/buildroot/buildroot/archive/refs/tags/2023.05-rc2.tar.gz
	tar -xzf buildroot.tar.gz
	$(RM) buildroot.tar.gz
	mv buildroot-2023.05-rc2 $@

$(BUILDROOT_DIR)/.config:
	cp $(BUILDROOT_CFG) $@

$(BUILDROOT_DIR)/kernel.config:
	cp $(KERNEL_CFG) $@

$(BUILDROOT_DIR)/busybox.config:
	cp $(BUSYBOX_CFG) $@

.PHONY: $(BUILDROOT_DIR)/output/images/Image
$(BUILDROOT_DIR)/output/images/Image: $(BUILDROOT_DIR) $(BUILDROOT_DIR)/.config $(BUILDROOT_DIR)/kernel.config $(BUILDROOT_DIR)/busybox.config
	mkdir -p buildroot/output/target/
	cp -r $(wildcard extra/*) buildroot/output/target/
	make -C buildroot

# The buildroot-generated fw_payload.bin seems to chop off the end of the kernel image sometimes,
# so we assemble the image ourselves.
linux_image.bin: $(BUILDROOT_DIR)/output/images/Image
	cp $(BUILDROOT_DIR)/output/images/fw_jump.bin linux_image.bin
# Enlarge the OpenSBI image to exactly 4MiB. This alignment is required by OpenSBI.
	dd if=/dev/zero bs=1 seek=4194304 count=0 of=linux_image.bin
# Append the actual kernel image
	cat $(BUILDROOT_DIR)/output/images/Image >> linux_image.bin
	
# Pack the raw image into a dummy ELF for VTop to read
linux_image.elf: linux_image.bin
	$(RV32_OBJCOPY) -B riscv --input-target=binary --output-target=elf32-little linux_image.bin linux_image.elf
# Rename .data to .text for the testbench to execute it
	$(RV32_OBJCOPY) -B riscv --input-target=elf32-little --rename-section .data=.text --output-target=elf32-little linux_image.elf

.PHONY: clean
clean:
	$(RM) -r $(BUILDROOT_DIR) linux_image.elf linux_image.bin
