from pathlib import Path
import json
import argparse
import configparser
import re
import subprocess
from string import Template

# This is a quick and dirty install script for
# a Verilog submodule in a Git managed repo. It looks for:
# - sources.txt
# - simulation.txt
# - constraints.txt
# - ips.txt
# - simips.txt
# - repos.json
# in the directory passed to it.
#
# You MUST be in the main git repository that you're
# trying to install.
#
# The repos.json file allows the submodule to add dependencies and
# also allows for template-replacing the sources.txt file.
#
# You MUST have at the very least a sources.txt file and a repos.json
# file.
#
# The repos.json file contains:
# 1: a key for the repo being installed. This is used
#    as a template replace for the source tracking files
#    (e.g. ${VERILOGLIB}/hdl/flag_sync.v).
#
# You need at least one key which is empty. This is the current module,
# and is used for template replacing in the source tracking files.
#
# 2: a "url" value: This is the submodule to be added. If it isn't
#    present, no Git submodule is added.
# 3: a "default" value. This is the default name for the submodule's
#    location.
# 4: a "repository" key. This is either true or false, and by default
#    it is false. If it's true, it's treated as an IP repository to
#    be added in the project_init.tcl script.
#
# You MAY have a constraints.txt, ips.txt, simips.txt, simulation.txt.
#
# You MAY also have a submodule_init.tcl.tmpl file. This will be turned
# into an {submodule location}_init.tcl. This can be overwritten with
# the --sminit parameter.
#
# You can override the 'default' destination location by using
# an argument named as the key (e.g. --VERILOGLIB=verilog-library-barawn).
#
# You can add a prefix to all locations with the --prefix option.
#
# If you run this command when a submodule is already installed, it
# won't screw anything up, it'll automatically detect that things have been
# run. It will also actually update anything that needs to be updated.

# Match up submodules from repos.json to the
# ones in the gitmodules file if possible and if found,
# update the dictionary with their path.
#
# We always fetch https submodules, but we'll match against
# SSH ones so we need to regex extract host/owner/repo tags to compare.
# We don't bother with requiring like, a specific tag or something.
# Whatever. Keep forward compatibility.
def submodule_match( sm_this, sm_dict ):
    repo_regex = re.compile("(?P<proto>git@|https://)(?P<host>[\w\.@]+)(/|:)(?P<owner>[\w,\-,\_]+)/(?P<repo>[\w,\-,\_]+)(.git){0,1}((/){0,1})")

    # First start by building a list of the existing submodules.
    current_submodules = {}
    if Path(".gitmodules").exists():
        submodule_config = configparser.ConfigParser()
        # URLs in our submodule list are all https URLs.
        # To match to SSH URLs when searching, we need to regex extract
        # the host/owner/repo tags to compare.
        submodule_config.optionxform = str
        submodule_config.read(".gitmodules")
        for sm in submodule_config:
            if 'url' in submodule_config[sm]:
                matches = repo_regex.search(submodule_config[sm].get('url'))
                # to create a hashable type we make a list of host/owner/repo
                host = matches['host']
                owner = matches['owner']
                repo = matches['repo']
                current_submodules[(host, owner, repo)] = submodule_config[sm].get('path')

    print("Checking submodule dependencies:")
    sm_dep = {}
    key_map = {}
    for k in sm_dict:
        if k != sm_this:
            matches = repo_regex.search(sm_dict[k]['url'])
            host = matches['host']
            owner = matches['owner']
            repo = matches['repo']
            sm_dep[(host, owner, repo)] = sm_dict[k]['default']
            key_map[(host, owner, repo)] = k

    missing_sm = {}
    for sm in sm_dep:
        if sm in current_submodules:
            sm_dep[sm] = current_submodules[sm]
            print("Matched existing submodule ",sm," at ", sm_dep[sm])
            # Now replace the path in the sm_dict as well.
            # Above we create a triplet-to-path mapping for Git
            # submodule install. This updates it for the template replace.
            sm_dict[key_map[sm]]['default'] = sm_dep[sm]
        else:
            print("Need to fetch submodule ",sm)
            missing_sm[sm] = sm_dep[sm]
    return (sm_dep, missing_sm)



parser = argparse.ArgumentParser( prog='install.py',
                                  description='Install a submodule into a Git managed repo',
                                  add_help=False)

parser.add_argument("directory", help="Path to submodule")
parser.add_argument("-s", "--simulate", help="Do a dry run (don't actually change anything)",
                    action='store_true')
args, unknown = parser.parse_known_args()

# We need to two-stage parse the arguments, since we want to
# find what options are in the JSON file. At the very least
# we need a sources.txt and a repos.json.

this_dir = Path(args.directory)
if not this_dir.exists():
    print("Submodule path '" + this_dir + "' does not exist!")
    exit(1)
sourcepath = this_dir / "sources.txt"
if not sourcepath.exists():
    print("No sources.txt file found in '"+this_dir+"'!")
    exit(1)
repopath = this_dir / "repos.json"
if not repopath.exists():
    print("No repos.json file found in '"+this_dir+"'!")
    exit(1)

cursourcepath = Path("sources.txt")
if not cursourcepath.exists():
    print("No sources.txt found in current directory!")
    print("Need to be in the top directory of a Git managed repository.")
    exit(1)

curinitpath = Path("project_init.tcl")
if not curinitpath.exists():
    print("No project_init.tcl found in current directory!")
    print("Need to be in the top directory of a Git managed repository.")
    exit(1)

with open(repopath) as repos_json:
    d = json.load(repos_json)

# First, loop through the repos.json to find the empty one.
# (that's referring to this repository)
this_repo = None
for k in d:
    if d[k] == {}:
        if this_repo is None:
            this_repo = k
        else:
            print("More than one entry is empty!")
            print("First entry: '"+this_repo+"'")
            print("Second entry: '"+k+"'")
            print("Only one entry (the repo itself) can be empty.")
            print("The other entries must have at least a 'default' entry.")
            exit(1)
            
if this_repo is None:
    print("Unable to identify this repo in repos.json (no entry without 'url')!")
    exit(1)
else:
    print("Installation script for submodule using replacement key "+this_repo)

# Determine if we need to add the --sminit parameter.
sminitpath = this_dir/"submodule_init.tcl.tmpl"
print("Checking for %s" % sminitpath)
smdefault = this_dir.name+"_init.tcl"
if sminitpath.exists():
    parser.add_argument("--sminit",
                        default=smdefault,
                        help='Name of the submodule initialization Tcl file to generate')
else:
    print("No sminit")
    
for k in d:
    if k != this_repo:
        parser.add_argument('--'+k, help="Install location for '"+k+"' submodule")

# Restore the help argument
parser.add_argument("-h", "--help", action='help', default=argparse.SUPPRESS,
                    help='show this help message and exit')
# And the prefix argument
parser.add_argument("-p", "--prefix", help="Prefix to append to all defaults")
args = parser.parse_args()
pfx = '' if not args.prefix else args.prefix

print("==== Checking submodule dependencies ====")

# Build the paths for the submodules
dargs = vars(args)
for k in d:
    if k != this_repo:
        default_path = Path(pfx)/Path(d[k]['default'])
        d[k]['default'] = dargs[k] if dargs[k] else default_path

sm_dep, missing_sm = submodule_match(this_repo, d)

if len(sm_dep):
    print("Need to install %d/%d dependenc%s" % (len(missing_sm), len(sm_dep), "y" if len(sm_dep)==1 else "ies"))
    if len(missing_sm):
        for sm in missing_sm:
            built_path = "https://" + sm[0] + "/" + sm[1] + "/" + sm[2]
            print("Adding submodule %s at path %s" % (built_path, missing_sm[sm]))
            smargs = ["git", "submodule", "add", built_path, missing_sm[sm]]            
            if not args.simulate:
                subprocess.run(smargs)
            else:
                echo(' '.join(smargs))
                
print("==== Replacing templates: ====")
def template_quote(s):
    return "${"+s+"}"

ip_repos = []

templ_dict = {}
for k in d:
    if k == this_repo:
        templ_dict[k] = this_dir
        print(template_quote(this_repo),
              "=",
              this_dir)
    else:
        is_repo = d[k]['repository'] if 'repository' in d[k] else False
        if not is_repo:
            templ_dict[k] = d[k]['default']
            print(template_quote(k),
                  "=",
                  d[k]['default'])
        else:
            ip_repos.append(k)

def match_files(newf, oldf, templ):
    entries = []
    print("==== Matching %s entries in %s ====" % (newf, oldf))
    with open(newf, "r") as f:
        src = Template(f.read())
        entries = src.substitute(templ).splitlines()
    to_append = []
    if not oldf.exists():
        to_append = entries
        print("%s does not exist - need all %d entries" % (oldf, len(entries)))
    else:
        with open(oldf, "r") as f:
            cursrcs = set(f.read().splitlines())
            to_append = [item for item in entries if item not in cursrcs]
        print("Need to add %d/%d entries into %s" % (len(to_append), len(entries), oldf))
    return to_append

def add_entries(oldf, entries):
    with open(oldf, "a") as f:
        for entry in entries:
            print("Adding %s to %s" % (entry, oldf))
            if not args.simulate:
                f.write(src)

src_append = match_files(sourcepath, cursourcepath, templ_dict)
add_entries(cursourcepath, src_append)

ippath = Path(this_dir)/"ips.txt"
if ippath.exists():
    curippath = Path("ips.txt")
    ip_append = match_files(ippath, curippath, templ_dict)
    add_entries(curippath, ip_append)

simippath = Path(this_dir)/"simips.txt"
if simippath.exists():
    cursimippath = Path("simips.txt")
    simip_append = match_files(simippath, cursimippath, templ_dict)
    add_entries(cursimippath, simip_append)

constrpath = Path(this_dir)/"constraints.txt"
if constrpath.exists():
    curconstrpath = Path("constraints.txt")
    constr_append = match_files(constrpath, curconstrpath, templ_dict)
    add_entries(curconstrpath, constr_append)

simpath = Path(this_dir)/"simulation.txt"

if simpath.exists():
    cursimpath = Path("simulation.txt")
    sim_append = match_files(simpath, cursimpath, templ_dict)
    add_entries(cursimpath, sim_append)

# Add any ip repositories to the project_init.tcl file.
# First, create the exact line we want. We then need to search
# for either that line or that exact line with a # in front of it.
# Plus a utility text in front.
# -- automatically added by $(path) submodule: if unneeded, comment out.
# where 'path' is templ_dict[this_repo]



autoheader = "# -- automatically added by ${autopath} submodule: if unneeded, comment out."
autobody = "add_ip_repository [file join [get_repo_dir] ${autorepo}]"
autopath = templ_dict[this_repo]

print("=== Processing IP repositories added in project_init.tcl")

# Search for either an active add_ip_repository to the same location OR
# a commented out line to the same location (which indicates it's not needed
# for some reason)
repore = "^#?(\s*)(?P<iprepoline>add_ip_repository.*$)"
repolines = []
with open(curinitpath, "r") as f:
    for line in f.read().splitlines():        
        matches = re.match(repore, line)
        if matches:
            print("Found an IP repo add line already in project_init.tcl: ", line)
            repolines.append(line)

initlines = []
header = Template(autoheader).substitute(autopath=autopath)

for k in d:
    is_repo = d[k]['repository'] if 'repository' in d[k] else False
    if is_repo:
        repopath = d[k]['default']
        autorepo = ' '.join(Path(repopath).parts)
        rl = Template(autobody).substitute(autorepo=autorepo)
        for l in repolines:
            matches = re.match(repore, l)
            if matches['iprepoline'] == rl:
                print("IP repository at '%s' already in project_init.tcl ('%s')" % (d[k]['default'], l))
            else:
                initlines.append(rl)

if len(initlines):
    with open(curinitpath, "a") as f:
        print("Appending to project_init.tcl: ", header)
        if not args.simulate:
            f.write(autoheader)
        for l in initlines:
            print("Appending to project_init.tcl: ", l)
            if not args.simulate:
                f.write(l)

if sminitpath.exists():
    print("==== Processing generation and add of submodule init Tcl in project_init.tcl")

    sminit = "source [file join [get_repo_dir] "+" "+args.sminit+"]"
    sminitre = "^#?(\s*)"+sminit+".*$"

    # Generate the current text.
    sminittext = None
    with open(sminitpath, "r") as f:
        sminittext = Template(f.read()).substitute(templ_dict)
    # And output it. This will overwrite an existing file there. Maybe we'll add a
    # warning at some point, lol.
    if not args.simulate:
        with open(Path(args.sminit, "w")) as f:
            f.write(sminittext)

    # Now we need to look in project_init.tcl for sminit
    need_source = True
    with open(curinitpath, "r") as f:
        for line in f.read().splitlines():
            matches = re.match(sminitre, line)
            if matches:
                print("project_init.tcl already sources submodule init: %s", line)
                need_source = False
    if need_source:
        print("Appending source of submodule init in project_init.tcl.")
        if not args.simulate:
            with open(curinitpath, "a") as f:
                f.write(autoheader)
                f.write(sminit)
