# nio node Provisioning

Scripts and steps to set up a nio node for device management.

*Note:* This is not a getting started with nio guide. These files and the bootstrap script are intended to bring a new nio node up and running under nio's Enterprise Device Management. If you are looking to get started installing nio on your own devices check out the [Getting Started documentation](https://docs.n.io/installation/nio/).

You will need a valid device ID from the nio Device Management portal to run this script

## Quick Start
```bash
curl -s -L https://raw.githubusercontent.com/niolabs/provisioning/master/bootstrap.sh | bash
```

## Requirements
 - A shell capable of running `bash`
 - A device with `systemd` as its init script
 - A Python 3 executable and a `virtualenv` executable
 - A valid device ID from nio

## Bootstrapping a new device

### Ubuntu/Debian
```bash
sudo apt install python3 python3-virtualenv
curl -s -L https://raw.githubusercontent.com/niolabs/provisioning/master/bootstrap.sh | bash
```

### Mac OSX
Mac does not run systemd, so we skip that part.
```bash
brew install python3
pip3 install virtualenv
curl -s -L https://raw.githubusercontent.com/niolabs/provisioning/master/bootstrap.sh | BS_SKIP_SYSTEMD=1 bash
```
