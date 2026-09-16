# wine-builds
Use GitHub actions to build [wine](https://winehq.org).

Currently only built for AlmaLinux 10 (x86_64), but you can adapt it to your own. This acts as a template.

## Steps
The RPM needs EPEL for one dependency (`libunwind`); everything else comes from BaseOS/AppStream:
```sh
sudo dnf install -y epel-release
```

Then download the `wine-11.0-2.el10.x86_64.rpm` file from the [Releases Page](https://github.com/OreDakeDesu/wine-builds/releases) and run:
```sh
sudo dnf install -y ./wine-11.0-*.rpm
```

## Note
The actions utilise [blacksmith](https://soydev.link/blacksmith) (This referral link is for Theo [t3.gg](https://t3.gg)).

Blacksmith is a drop-in replacement to the default GitHub actions runners. It speeds up builds and is cheaper than GitHub actions. They give `3000` free monthly build minutes **(this is based on 2vCPUs, so if you use higher vCPUs, it scales based on that rate e.g. 8vCPUs will consume your quota 4 times faster)**