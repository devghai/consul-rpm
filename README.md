# RPM Spec for Consul

Tries to follow the [packaging guidelines](https://fedoraproject.org/wiki/Packaging:Guidelines) from Fedora.

* Binary: `/usr/bin/consul`
* Config: `/etc/consul.d/`
* Shared state: `/var/lib/consul/`
* Sysconfig: `/etc/sysconfig/consul`
* WebUI: `/usr/share/consul/`

Only supports SystemD.

# Build

There are a number of ways to build the `consul` and `consul-ui` RPMs:
* Manual
* Vagrant
* Docker

Each method ultimately does the same thing - pick the one that is most comfortable for you.

### Version

Use `build.sh -l` to see versions available for packaging. Script queries consul download URL to find available versions... so will need a network connection and `curl`.

## Manual

Build the RPM as a non-root user from your home directory:

* Check out this repo. Seriously - check it out. Nice.
    ```
    git clone <this_repo_url>
    ```

* Use `build.sh` to build the RPM. `build.sh -h` tells you all options that are available, along with respective default settings. It will build the latest version in current directory by default. Examples:
    ```
    # Build version 0.7.2
    build.sh -v 0.7.2

    # Build version 0.7.2 with RPM tree located in /tmp folder
    build.sh -v 0.7.2 -b /tmp

    # Build version 0.7.2 with RPM tree located in /tmp folder and set release version 'example'
    build.sh -v 0.7.2 -b /tmp -r example
    ```

## Vagrant

If you have Vagrant installed:

* Check out this repo.
    ```
    git clone https://github.com/tomhillable/consul-rpm
    ```

* Edit `Vagrantfile` to point to your favourite box (Bento CentOS7 in this example).
    ```
    config.vm.box = "http://opscode-vm-bento.s3.amazonaws.com/vagrant/virtualbox/opscode_centos-7.0_chef-provisionerless.box"
    ```

* Vagrant up! The RPMs will be copied to working directory after provisioning.
    ```
    vagrant up
    ```

## Docker

If you prefer building it with Docker:

* Build the Docker image. Note that you must amend the `Dockerfile` header if you want a specific OS build (default is `centos7`).
    ```
    docker build -t consul:build .
    ```

* Run the build.
    ```
    docker run -v $HOME/consul-rpms:/RPMS consul:build
    ```

* Retrieve the built RPMs from `$HOME/consul-rpms`.

# Result

Three RPMs:
- consul server
- consul web UI

# Run

* Install the RPM.
* Put config files in `/etc/consul.d/`.
* Change command line arguments to consul in `/etc/sysconfig/consul`.
  * Add `-bootstrap` **only** if this is the first server and instance.
* Start the service and tail the logs `systemctl start consul.service` and `journalctl -f`.
  * To enable at reboot `systemctl enable consul.service`.
* Consul may complain about the `GOMAXPROCS` setting. This is safe to ignore;
  however, the warning can be supressed by uncommenting the appropriate line in
  `/etc/sysconfig/consul`.

## Config

Config files are loaded in lexicographical order from the `config-dir`. Some
sample configs are provided.

# More info

See the [consul.io](http://www.consul.io) website.

# TODO

1. Earlier verisons of this package used `/etc/consul/` as the default
configuration directory. As of 0.7.2, the default directory was changed to
`/etc/consul.d/`. Need to add this in order to align with the offcial Consul docuemntation.
2. Logrotate config.
