#!/usr/bin/env python

import subprocess
import os
import sys
import re


lib_sysroot     = os.path.abspath(sys.argv[1])
octave_root     = os.path.abspath(sys.argv[2])
depsdir         = os.path.abspath(sys.argv[3])  


all_sysroot_libs = list(
    (os.path.join(dirpath, f)
         for dirpath,dirs,files in os.walk(lib_sysroot) for f in files if re.match(r'.+\.dylib', f)))


def has_rpath(lib):
    
    return re.match(r'^@rpath', lib) != None


def find_rpath_lib(lib):
    
    name = re.sub(r'^@rpath/', '', lib)
    g = (f for f in all_sysroot_libs if (os.path.basename(f) == name))
    try:
        return next(g)
    except StopIteration:
        raise Exception('Library {} not found in {}.'.format(lib, lib_sysroot))


def in_sysroot(lib):

    return (lib.find(lib_sysroot) == 0)


def in_octave(lib):

    return (lib.find(octave_root) == 0)


def is_system(lib):

    return lib.find('/System/') == 0 or lib.find('/usr/') == 0

    
def immediate_deps(fname):

    otool = subprocess.Popen(['/usr/bin/otool', '-L', fname], stdout=subprocess.PIPE)
    next(otool.stdout)
#    next(otool.stdout)
    for line in otool.stdout:
        lib = re.sub(r'\(.+\)', '', line)
        lib = lib.strip()
        if os.path.basename(lib) != os.path.basename(fname):
            yield lib


def process_file(fname, rpaths, visited):

    print ''
    print 'Starting processing of main target {} ...'.format(fname)
    print ''

    if fname in visited:
        return
    
    visited.add(fname)
    
    def descend(current_file, visited, rpaths):

        print 'Processing {} ...'.format(current_file)
        
        for f in immediate_deps(current_file):

            original_link_name = f
            
            print '-> Dependency {}'.format(f)

            if has_rpath(f):
                f = find_rpath_lib(f)
                
            if not (in_sysroot(f) or in_octave(f) or is_system(f)):
                raise Exception('Unforseen location of library {}.'.format(f))

            if is_system(f):
                continue

            new_link_name = os.path.join('@rpath', os.path.basename(f))
            os.system('install_name_tool -change {} {} {}'.format(original_link_name, new_link_name, current_file))
            
            if f in visited:
                continue

            visited.add(f)
            
            if in_sysroot(f):
                rpaths.add(depsdir)
                loc = os.path.join(depsdir, os.path.basename(f))
                os.system('cp -L {} {}'.format(f, loc))
                
            elif in_octave(f):
                rpaths.add(os.path.dirname(f))
                loc = f

            os.system('install_name_tool -id {} {}'.format(new_link_name, loc))
            descend(loc, visited, rpaths)

    descend(fname, visited, rpaths)
        

def files_to_process():

    find = subprocess.Popen(r"find {} \( -type f -perm +111 ! -iname '*.la' -or -type f -iname '*.oct' -or -type f -iname '*.dylib' \)".format(octave_root),
                            shell=True, stdout=subprocess.PIPE)
    return (f.strip() for f in find.stdout)


def clear_all_rpaths(f):

    cmd = r"/usr/bin/otool -l {} | grep LC_RPATH -A2 | grep path | sed 's/path//;s/([^)]*)//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'".format(f)
    otool = subprocess.Popen(args=cmd, shell=True, stdout=subprocess.PIPE)
    for p in otool.stdout:
        os.system(r'install_name_tool -delete_rpath {} {}'.format(p.strip(), f))


def executables():

    for f in ['octave-gui', 'octave-cli', 'mkoctfile', 'octave-config', 'gs']:
        yield subprocess.check_output('find {} -iname {}'.format(octave_root, f), shell=True).strip()
        

def add_rpaths(f, rpaths):

    for p in rpaths:
        relpath = os.path.relpath(p, os.path.dirname(f))
        rpath = os.path.join(r'@executable_path', relpath)
        os.system(r'install_name_tool -add_rpath {} {}'.format(rpath, f))

        


visited = set()
rpaths = set()

for f in files_to_process():
    process_file(f, rpaths, visited)
    
print 'Clearing rpaths ...'
for f in files_to_process():
    clear_all_rpaths(f)

print 'Adding rpaths ...'
print rpaths
for e in executables():
    add_rpaths(e, rpaths)

