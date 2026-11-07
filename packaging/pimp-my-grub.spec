Name:           pimp-my-grub
Version:        0.2.0
Release:        1%{?dist}
Summary:        Native Qt 6 GRUB theme builder
License:        GPL-3.0-or-later
URL:            https://github.com/pimp-my-grub/pimp-my-grub
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  cargo rust qt6-qtbase-devel qt6-qtdeclarative-devel clang-devel gcc-c++
Requires:       qt6-qtdeclarative polkit
Recommends:     grub2-tools

%description
Visual GRUB theme editor with a theme store and a reversible installer that shows
every change and asks for confirmation before touching /boot or /etc.

%prep
%autosetup -n %{name}-%{version}

%build
export QMAKE=${QMAKE:-/usr/bin/qmake6}
cargo build --release --locked -p pimp-my-grub

%install
sh packaging/install.sh %{buildroot} %{_prefix}

%files
%{_bindir}/pimp-my-grub
%{_libexecdir}/pimp-my-grub/pimp-my-grub-helper
%{_libexecdir}/pimp-my-grub/pimp-my-grub-bin
%{_datadir}/polkit-1/actions/dev.pimpmygrub.policy
%{_datadir}/applications/dev.pimpmygrub.PimpMyGrub.desktop
%{_datadir}/metainfo/dev.pimpmygrub.PimpMyGrub.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/pimp-my-grub.png
