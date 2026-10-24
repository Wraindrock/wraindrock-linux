# Draft unattended kickstart (Anaconda path).
# NOTE: Titanoboa's current ISO does not ship an Anaconda stage2, so this file
# only becomes usable if we add an Anaconda-enabled ISO variant.
lang en_US.UTF-8
keyboard us
timezone UTC
rootpw --lock
clearpart --all --initlabel
autopart --nohome --type=btrfs
reboot --eject
%post --erroronfail
set -e
bootc switch --mutate-in-place --transport registry ghcr.io/wraindrock/wraindrock-linux:44
%end
