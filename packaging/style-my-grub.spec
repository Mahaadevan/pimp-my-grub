Name:           style-my-grub
Version:        0.6.3
Release:        1%{?dist}
Summary:        Native Qt 6 GRUB theme builder
License:        GPL-3.0-or-later
URL:            https://github.com/style-my-grub/style-my-grub
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  cargo rust qt6-qtbase-devel qt6-qtdeclarative-devel clang-devel gcc-c++
Requires:       qt6-qtdeclarative polkit
Recommends:     grub2-tools
Recommends:     (zenity or kdialog)

%description
Visual GRUB theme editor with a theme store and a reversible installer that shows
every change and asks for confirmation before touching /boot or /etc.

%prep
%autosetup -n %{name}-%{version}

%build
export QMAKE=${QMAKE:-/usr/bin/qmake6}
cargo build --release --locked -p style-my-grub

%install
sh packaging/install.sh %{buildroot} %{_prefix}

%files
%{_bindir}/style-my-grub
%{_libexecdir}/style-my-grub/style-my-grub-helper
%{_libexecdir}/style-my-grub/style-my-grub-bin
%{_datadir}/polkit-1/actions/dev.stylemygrub.policy
%{_datadir}/applications/dev.stylemygrub.StyleMyGrub.desktop
%{_datadir}/metainfo/dev.stylemygrub.StyleMyGrub.metainfo.xml
%{_datadir}/icons/hicolor/*/apps/dev.stylemygrub.StyleMyGrub.png
