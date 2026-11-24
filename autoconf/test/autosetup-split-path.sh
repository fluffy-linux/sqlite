#! /bin/sh
# Test autosetup's PATH search (split-path / find-executable-path) with
# PATH entries that contain glob metacharacters: a directory whose name
# ends in a backslash, an unbalanced '{', a literal '[1]' directory that
# must win over its glob match, literal braces, and bracket expressions
# that contain ':' ('[[:alpha:]]', '[b:]') and so must not be split.
# The same auto.def is run under tclsh and under a freshly built jimsh0.
#
# Known failure (reported as XFAIL, an unexpected pass fails the test):
# neither Tcl's nor Jim's glob understands POSIX character classes, so a
# '[[:alpha:]]' entry is kept whole but matches nothing.
#
# Every fixture lives under a temporary directory.  The tools autosetup
# needs to run "use cc" (cc, ar, strip, and whatever cc and config.guess
# run) are reached only through symlinks in that directory, built from
# whatever the caller's PATH provides.
#
# Usage: CC=cc TCLSH=tclsh $(SHELL) test/autosetup-split-path.sh TOP

top=${1:?usage: $0 TOP}
case $top in /*) ;; *) top=$(pwd)/$top ;; esac
: "${CC:=cc}"
: "${TCLSH:=tclsh}"
td="$(mktemp -d)" || exit 99
trap 'rm -rf "$td"' EXIT
fail=0

probe() {
    mkdir -p "$1" && : > "$1/$2" && chmod 755 "$1/$2" || exit 99
}

# A farm of every executable on the caller's PATH, first match wins.
# Unquoted $PATH lets the shell expand wildcard entries such as /sw/*/bin.
farm="$td/sw/host/bin"
mkdir -p "$farm" || exit 99
oldifs=$IFS
IFS=:
for d in $PATH
do
    IFS=$oldifs
    case $d in /*) ;; *) continue ;; esac
    for f in "$d"/*
    do
        n=${f##*/}
        test -f "$f" && test -x "$f" || continue
        test -e "$farm/$n" || test -h "$farm/$n" || ln -s "$f" "$farm/$n" || exit 99
    done
done
IFS=$oldifs
probe "$farm" host_probe

ccname=${CC%% *}
case $ccname in
    /*) cctarget=$ccname ;;
    *) cctarget=$farm/$ccname ;;
esac
for t in "$cctarget" "$farm/ar" "$farm/strip"
do
    if ! test -x "$t"
    then
        echo "ERROR: $t not found on PATH" >&2
        exit 99
    fi
done

# Tools reachable only through bracket expressions containing ':'.
mkdir -p "$td/al/gcc/bin" "$td/bn/binutils/bin" || exit 99
ln -s "$cctarget" "$td/al/gcc/bin/cc" || exit 99
ln -s "$farm/ar" "$td/bn/binutils/bin/ar" || exit 99
ln -s "$farm/strip" "$td/bn/binutils/bin/strip" || exit 99
# Sorts before gcc: found first if [[:alpha:]] matched a digit.
probe "$td/al/1cc/bin" cc

# Literal directories with metacharacters in their names.
probe "$td/dir_bs\\" bs_probe
probe "$td/{unclosed_x" unclosed_probe
probe "$td/lit[1]/bin" lit_probe
probe "$td/lit1/bin" lit_probe
probe "$td/br{a,b}/pkg/bin" br_probe

cat > "$td/auto.def" <<'EOF'
use cc
set td [getenv TD]
set fail 0
proc expect-path {name want} {
    set got [find-executable-path $name]
    if {$got ne $want} {
        puts "FAIL: $name: got '$got', want '$want'"
        incr ::fail
    } else {
        puts "PASS: $name -> $got"
    }
}
proc xfail-path {name want why} {
    set got [find-executable-path $name]
    if {$got ne $want} {
        puts "XFAIL: $name: got '$got', want '$want' ($why)"
    } else {
        puts "XPASS: $name -> $got"
        incr ::fail
    }
}
foreach t {cc ar strip} {
    if {![cc-check-progs $t]} {
        puts "FAIL: cc-check-progs $t"
        incr fail
    }
}
expect-path bs_probe "$td/dir_bs\\/bs_probe"
expect-path unclosed_probe "$td/\{unclosed_x/unclosed_probe"
expect-path lit_probe "$td/lit\[1\]/bin/lit_probe"
expect-path br_probe "$td/br{a,b}/pkg/bin/br_probe"
# A ':' inside a bracket expression must not split the entry: split
# pieces 'alpha' and ']inutils/bin' exist relative to the run directory.
expect-path split_probe ""
xfail-path cc "$td/al/gcc/bin/cc" "glob has no \[:alpha:\] class"
expect-path ar "$td/bn/binutils/bin/ar"
expect-path strip "$td/bn/binutils/bin/strip"
expect-path host_probe "$td/sw/host/bin/host_probe"
if {$fail} {
    user-error "$fail PATH search check(s) failed"
}
EOF

p="$td/dir_bs\\:$td/{unclosed*:$td/lit[1]/bin:$td/br{a,b}/*/bin"
p="$p:$td/al/[[:alpha:]]*/bin:$td/bn/[b:]inutils/bin:$td/sw/*/bin"

run() {
    label=$1
    shift
    rm -rf "$td/run" && mkdir "$td/run" && cp "$td/auto.def" "$td/run/" || exit 99
    probe "$td/run/alpha" split_probe
    probe "$td/run/]inutils/bin" split_probe
    if (
        cd "$td/run" || exit 99
        unset CC
        TD="$td" CROSS="" PATH="$p" "$@" "$top/autosetup/autosetup"
    ) > "$td/$label.log" 2>&1
    then
        grep -E '^(PASS|XFAIL)' "$td/$label.log" | sed "s|^|$label: |"
        echo "PASS: $label"
    else
        cat "$td/$label.log"
        echo "FAIL: $label"
        fail=1
    fi
}

tclsh_path=$(command -v "$TCLSH" 2>/dev/null)
if test -n "$tclsh_path"
then
    run tclsh "$tclsh_path"
else
    echo "SKIP: tclsh: $TCLSH not found"
fi

if $CC -O1 "$top/autosetup/jimsh0.c" -o "$td/jimsh0" > "$td/jimsh0-build.log" 2>&1
then
    run jimsh0 "$td/jimsh0"
else
    cat "$td/jimsh0-build.log"
    echo "FAIL: building jimsh0"
    fail=1
fi

exit $fail
