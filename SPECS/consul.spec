# Spec file to build RPM for Consul and its web ui.
# Docs for scriptlets/macros: https://fedoraproject.org/wiki/Packaging:Scriptlets?rd=Packaging:ScriptletSnippets

Name:           consul
Version:        %{pkg_version}
Release:        %{rpm_release}%{?dist}
Summary:        Consul is a tool for service discovery and configuration. Consul is distributed, highly available, and extremely scalable.

Group:          System Environment/Daemons
License:        MPLv2.0
URL:            http://www.consul.io
Source0:        %{name}_%{pkg_version}_linux_amd64.zip
Source1:        %{name}.env.conf
Source2:        %{name}.service
Source3:        %{name}.json
Source4:        %{name}.logrotate
Source5:        %{name}.rsyslog.conf
BuildRoot:      %{buildroot}
BuildArch:      x86_64
BuildRequires:  systemd-units
Requires:       systemd, logrotate, rsyslog > 7.2
Requires(pre):  shadow-utils

%description
Consul is a tool for service discovery and configuration. Consul is distributed, highly available, and extremely scalable.

Consul provides several key features:
 - Service Discovery - Consul makes it simple for services to register themselves and to discover other services via a DNS or HTTP interface. External services such as SaaS providers can be registered as well.
 - Health Checking - Health Checking enables Consul to quickly alert operators about any issues in a cluster. The integration with service discovery prevents routing traffic to unhealthy hosts and enables service level circuit breakers.
 - Key/Value Storage - A flexible key/value store enables storing dynamic configuration, feature flagging, coordination, leader election and more. The simple HTTP API makes it easy to use anywhere.
 - Multi-Datacenter - Consul is built to be datacenter aware, and can support any number of regions without complex configuration.

%prep

# docs: https://docs.fedoraproject.org/en-US/Fedora_Draft_Documentation/0.1/html-single/RPM_Guide/index.html#id853841
%setup -q -c

%install
# Binary
mkdir -p %{buildroot}/%{_bindir}
cp consul %{buildroot}/%{_bindir}

# JSON Configs
mkdir -p %{buildroot}/%{_sysconfdir}/%{name}.d
cp %{SOURCE3} %{buildroot}/%{_sysconfdir}/%{name}.d/consul.json

# Data directories
mkdir -p %{buildroot}/%{_sharedstatedir}/%{name}

# Directory for storing log files.
mkdir -p %{buildroot}/%{_localstatedir}/log/%{name}

# Logrotate config
mkdir -p %{buildroot}%{_sysconfdir}/logrotate.d/
cp %{SOURCE4} %{buildroot}%{_sysconfdir}/logrotate.d/%{name}.conf

# RSyslog config to enable writing to a file.
mkdir -p %{buildroot}%{_sysconfdir}/rsyslog.d/
cp %{SOURCE5} %{buildroot}%{_sysconfdir}/rsyslog.d/%{name}.conf

# SystemD Unit definition.
mkdir -p %{buildroot}/%{_unitdir}
cp %{SOURCE2} %{buildroot}/%{_unitdir}/

# Environment settings to go alongside unit file.
mkdir -p %{buildroot}/%{_unitdir}/%{name}.service.d
cp %{SOURCE1} %{buildroot}/%{_unitdir}/%{name}.service.d/%{name}.env.conf

%pre
getent group consul >/dev/null || groupadd -r consul
# Setting shell for consul user to /sbin/nologin causes script based health checks to fail.
# See https://github.com/hashicorp/consul/issues/2999
getent passwd consul >/dev/null || \
    useradd -r -g consul -d /var/lib/consul -s /sbin/nologin \
    -c "consul.io user" consul
exit 0

%post
# SystemD related scriptlets: https://fedoraproject.org/wiki/Packaging:Scriptlets?rd=Packaging:ScriptletSnippets#Systemd
# https://github.com/systemd/systemd/blob/master/src/core/macros.systemd.in
%systemd_post %{name}.service

echo
echo "NOTES ############################################################################"
echo "Please restart RSyslog so that logs are written to %{_localstatedir}/log/%{name}:"
echo "    systemctl restart rsyslog.service"
echo "To have %{name} start automatically on boot:"
echo "    systemctl enable %{name}.service"
echo "Start %{name}:"
echo "    systemctl daemon-reload"
echo "    systemctl start %{name}.service"
echo "##################################################################################"
echo

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun_with_restart %{name}.service

%clean
rm -rf %{buildroot}

# Docs:
# https://fedoraproject.org/wiki/How_to_create_an_RPM_package#.25files_section
# https://fedoraproject.org/wiki/Packaging:Guidelines#Logrotate_config_file
%files
%defattr(-,root,root,-)
%attr(755, root, root) %{_bindir}/consul
%config(noreplace) %attr(640, root, consul) %{_sysconfdir}/%{name}.d/consul.json
%config(noreplace) %attr(644, root, root) %{_sysconfdir}/logrotate.d/%{name}.conf
%config(noreplace) %attr(644, root, root) %{_sysconfdir}/rsyslog.d/%{name}.conf
%config(noreplace) %{_unitdir}/%{name}.service.d/%{name}.env.conf

# Directory for logs. Renders to /var/log/consul
%dir %attr(750, consul, consul) %{_localstatedir}/log/%{name}
%dir %attr(750, consul, consul) %{_sharedstatedir}/%{name}
%dir %attr(750, root, consul) %{_sysconfdir}/%{name}.d
%{_unitdir}/%{name}.service

%doc

%changelog
* Tue Nov 28 2017 Dev <talk@devghai.com>
- Commenting out CMD_OPTS line in consul.env.conf as consul v1.0.1 fails to start with empty string as an argument.

* Fri Jul 21 2017 Dev <talk@devghai.com>
- Removing shell for consul user as v0.9.0 introduces disable-script-checks config.
- Removing separate UI packaging code as 0.9.0 no longer supports it.

* Tue May 30 2017 Dev <talk@devghai.com>
- Updating SystemD service definition to restart on failure.

* Tue May 09 2017 Dev <talk@devghai.com>
- Adding dependency on logrotate.

* Fri Apr 14 2017 Dev <talk@devghai.com>
- Remove SysV/Upstart support.
- Replace manual packaging steps with a script.
- Remove .json-dist. Backup on upgrade.

* Wed Apr 05 2017 mh <mh@immerda.ch>
- Bump to 0.8.0
- remove legacy location /etc/consul/

* Tue Feb 21 2017 Rumba <ice4o@hotmail.com>
- Bump to 0.7.5

* Wed Feb 8 2017 Jasper Lievisse Adriaanse <j@jasper.la>
- Bump to 0.7.4

* Thu Jan 26 2017 mh <mh@immerda.ch>
- Bump to 0.7.3

* Fri Dec 23 2016 Michael Mraz <michaelmraz@gmail.com>
- Change default configs directory to /etc/consul.d and /etc/consul-template.d
  while the old ones are still supported

* Thu Dec 22 2016 Rumba <ice4o@hotmail.com>
- Bump to 0.7.2

* Wed Dec 14 2016 Rumba <ice4o@hotmail.com>
- Bump to 0.7.1

* Wed Sep 21 2016 Rumba <ice4o@hotmail.com>
- Bump to 0.7.0

* Tue Jun 28 2016 Konstantin Gribov <grossws@gmail.com>
- Bump to v0.6.4

* Sun Jan 31 2016 mh <mh@immerda.ch>
- Bump to v0.6.3

* Fri Dec 11 2015 mh <mh@immerda.ch>
- Bump to v0.6

* Sun Oct 18 2015 mh <mh@immerda.ch>
- logrotate logfile on EL6 - fixes #14 & #15

* Tue May 19 2015 nathan r. hruby <nhruby@gmail.com>
- Bump to v0.5.2

* Fri May 15 2015 Dan <phrawzty@mozilla.com>
- Bump to v0.5.1

* Mon Mar 9 2015 Dan <phrawzty@mozilla.com>
- Internal maintenance (bump release)

* Fri Mar 6 2015 mh <mh@immerda.ch>
- update to 0.5.0
- fix SysV init on restart
- added webui subpackage
- include statedir in package
- run as unprivileged user
- protect deployed configs from overwrites

* Thu Nov 6 2014 Tom Lanyon <tom@netspot.com.au>
- updated to 0.4.1
- added support for SysV init (e.g. EL <7)

* Wed Oct 8 2014 Don Ky <don.d.ky@gmail.com>
- updated to 0.4.0
