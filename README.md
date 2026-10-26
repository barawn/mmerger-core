# HELIX Master Merger core logic

This repository factors out the Xillybus and frame buffer memory
from the rest of the master merger logic, which allows modifications
to the firmware and porting to different devices without changing
the base logic.

The IP cores in "ip" should always be configured for the base
master merger device - other ports will need to reconfigure them
and ensure the modified cores aren't pushed to the repository.

The ''sources.txt' and ''ips.txt'' should be appended to the
source tracking files for the port: note that this either
requires other submodules in specific locations or it requires
editing the source tracking files.

* ''verilog-library-barawn''
* ''dnpcie_aurora_v2''
* ''mmerger-core''
* ''verilog-axis''

Additionally the ''verilog_custom_ip'' repository must be available.

Eventually this will change to Python setup script to install into a
new repository.