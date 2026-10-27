from pathlib import Path
import json
import argparse
import configparser
import re
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
# You can override the 'default' destination location by using
# an argument named as the key (e.g. --VERILOGLIB=verilog-library-barawn).
#
# You can add a prefix to all locations with the --prefix option.

def submodule_match( sm_this, sm_dict ):
    # This is our submodule matcher. We always fetch https submodules,
    # but we'll match against SSH ones so we need to regex extract
    # host/owner/repo tags to compare.
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
    for k in sm_dict:
        if k != sm_this:
            matches = repo_regex.search(sm_dict[k]['url'])
            host = matches['host']
            owner = matches['owner']
            repo = matches['repo']
            sm_dep[(host, owner, repo)] = sm_dict[k]['default']

    missing_sm = {}
    for sm in sm_dep:
        if sm in current_submodules:
            sm_dep[sm] = current_submodules[sm]
            print("Matched existing submodule ",sm," at ", sm_dep[sm])
        else:
            print("Need to fetch submodule ",sm)
            missing_sm[sm] = sm_dep[sm]
    return (sm_dep, missing_sm)



parser = argparse.ArgumentParser( prog='install.py',
                                  description='Install a submodule into a Git managed repo',
                                  add_help=False)

parser.add_argument("directory", help="Path to submodule")

args, unknown = parser.parse_known_args()

# We need to two-stage parse the arguments, since we want to
# find what options are in the JSON file. At the very least
# we need a sources.txt and a repos.json.

dir = Path(args.directory)
if not dir.exists():
    print("Submodule path '" + dir + "' does not exist!")
    exit(1)
sourcepath = dir / "sources.txt"
if not sourcepath.exists():
    print("No sources.txt file found in '"+dir+"'!")
    exit(1)
repopath = dir / "repos.json"
if not repopath.exists():
    print("No repos.json file found in '"+dir+"'!")
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

# Build the paths for the submodules
dargs = vars(args)
for k in d:
    if k != this_repo:
        default_path = Path(pfx)/Path(d[k]['default'])
        if dargs[k]:
            d[k]['default'] = dargs[k]

sm_dep, missing_sm = submodule_match(this_repo, d)

if len(sm_dep):
    print("Need to install %d/%d dependenc%s" % (len(missing_sm), len(sm_dep), "y" if len(sm_dep)==1 else "ies"))
