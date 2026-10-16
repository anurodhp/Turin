#!/bin/sh
# Turin guest-side check, run as root inside the QEMU guest by tests/turin_qemu_test.sh (copied to
# /var/root/turin_verify.sh). Turin runs under Window Maker on Xvfb :0 (QEMU has no HDMI framebuffer), with gdnc started
# first as the session autostart does. Screenshots (xwd) land in /var/root/turintest:
#  1-5. each pane, chosen by clicking its sidebar row;
#  6.   Users: + opens New User; the fields are filled one by one (xtest_type sends Return after each, which the dialog
#       answers with what is still missing until the last one creates the account);
#  7.   the account in /etc/master.passwd with a DES hash, and its home folder.
T=/var/root/turintest
X=/usr/X11/bin
W=${TURIN_WAIT:-900}
rm -rf $T; mkdir -p $T
export HOME=/var/root DISPLAY=:0 GNUSTEP_CONFIG_FILE=/etc/GNUstep/GNUstep.conf
[ -f /System/Library/Makefiles/GNUstep.sh ] && . /System/Library/Makefiles/GNUstep.sh
shot() { $X/xwd -root -out $T/$1.xwd; echo "shot $1 rc=$?"; }

echo "== zones: $(grep -vc '^#' /var/db/timezone/zoneinfo/zone.tab 2>/dev/null) in zone.tab; localtime -> $(readlink /var/db/timezone/localtime)"
$X/Xvfb :0 -screen 0 1024x768x24 -nolisten tcp > $T/xvfb.log 2>&1 &
sleep 20
/usr/local/bin/gdnc > $T/gdnc.log 2>&1 &
$X/wmaker > $T/wmaker.log 2>&1 &
sleep 30
/Applications/Turin.app/Turin -TurinPane Wi-Fi > $T/turin.log 2>&1 &
# GNUstep starts slowly under QEMU/TCG (minutes): wait for the window (titled after the pane) to be mapped
i=0
while [ $i -lt $W ]; do
    $X/x11_probe tree 2>/dev/null | grep 'name=Wi-Fi$' | grep -q ' viewable' && break
    sleep 5; i=$((i + 5))
done
echo "window after ${i}s"
$X/x11_probe tree > $T/tree.txt 2>&1
sleep ${SETTLE:-40}
# the content area: the 800x560 window (sidebar 210 + pane 590)
G=$(grep ' 800x560+' $T/tree.txt | grep viewable | head -1 | sed 's/.* 800x560+\([0-9-]*\)+\([0-9-]*\) .*/\1 \2/')
set -- $G
WX=${1:-112}; WY=${2:-104}
echo "content at $WX,$WY"
shot 1_wifi
n=2
for pane in network datetime background users; do
    # sidebar row i: centre 36 + 36 i from the top, x 105
    $X/x11_probe click $((WX + 105)) $((WY + 36 + 36 * (n - 1)))
    sleep 40
    shot ${n}_$pane
    n=$((n + 1))
done

echo "== New User"
$X/x11_probe click $((WX + 247)) $((WY + 528))	# the + button
sleep 30
shot 6a_newuser
# field centres in the 800x560 content (see TurinDialogView's layout): x 460; y 316, 282, 248, 214 from the bottom
$X/x11_probe click $((WX + 460)) $((WY + 560 - 316)); sleep 5; $X/xtest_type "Ada Lovelace"; sleep 15
$X/x11_probe click $((WX + 460)) $((WY + 560 - 248)); sleep 5; $X/xtest_type babbage1; sleep 15
shot 6b_partial
$X/x11_probe click $((WX + 460)) $((WY + 560 - 214)); sleep 5; $X/xtest_type babbage1; sleep 40
shot 6c_created
echo "== account"
grep '^adalovelace:' /etc/master.passwd | awk -F: '{ print $1, "hash=" substr($2, 1, 1) "...(" length($2) ")", "uid=" $3, "gid=" $4, "gecos=" $8, "home=" $9, "shell=" $10 }'
ls -ld /Users/adalovelace 2>&1
grep '^staff:\|^admin:' /etc/group
echo "== log"
cat $T/turin.log | tail -40
pkill -x Turin; pkill -x wmaker; pkill -x gdnc; pkill -x Xvfb
echo "TURIN_TEST DONE"
