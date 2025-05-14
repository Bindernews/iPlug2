#!/usr/bin/env python3

# Copyright (C) the iPlug 2 Developers. Portions copyright other contributors, see each source file for more information.
# 
# This software is provided 'as-is', without any express or implied warranty.  In no event will the authors be held liable for any damages arising from the use of this software.
#
# Permission is granted to anyone to use this software for any purpose, including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
#
# 1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation would be appreciated but is not required.
# 2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
# 3. This notice may not be removed or altered from any source distribution.

"""
This module is a collection of utility functions that are eaiser to implement
in Python than in CMake. The CMake code calls these via CLI, and the inputs
and outputs are specifically formatted to make it easy for CMake.
"""

import argparse
import sys
from pathlib import Path

def parse_version(s: str) -> 'list[int]':
  """Parse a version string into a list of 4 integers: major, minor, patch, tweak."""
  result = []
  for p in s.split('.'):
    try:
      x = int(p, 10)
      result.append(x)
    except ValueError:
      # For now, just eat the error and silently ignore it
      pass
  while len(result) < 4:
    result.append(0)
  return result

def do_hex_version(s: str) -> str:
  ver = parse_version(s)
  # Use two hex digits for major version, and ignore tweak.
  # This is because many orgs are using the year as the major version now.
  return f'0x{ver[0]:04x}{ver[1]:02x}{ver[2]:02x}'

def guess_file_type(path: Path) -> str:
  ext = path.suffix
  if ext == ".ttf":
    return "font,ttf"
  elif ext == ".fon":
    return "font,fon"
  elif ext in (".png", ".gif", ".tiff"):
    return "image,raster"
  elif ext in (".svg"):
    return "image,vector"
  elif ext == ".ico":
    return "image,icon"
  elif ext == ".xib":
    return "xib,misc"
  elif ext in (".md"):
    return "text,markdown,doc"
  elif ext in (".txt"):
    return "text"
  elif ext in (".c", ".cpp", ".cxx", ".h", ".hpp", ".hxx"):
    return "text,code,cpp"
  elif ext in (".rs", ".lua", ".cmake", ".make", ".py", ".sh", ".bat", ".pl", ".php", ".rb"):
    return "text,code"
  elif ext in (".xml", ".storyboard"):
    return "text,xml"
  elif ext == ".plist":
    return "text,xml,plist"
  else:
    return "misc"
  


def make_parser(prog: str = 'cmutil.py'):
  parser = argparse.ArgumentParser(prog=prog)
  grp1 = parser.add_mutually_exclusive_group()
  grp1.add_argument('--hex-version', type=str, help='Convert a version string into a hex number')
  grp1.add_argument('--guess-file-types', type=str, help='Guess the file types of a list of files, semicolon-separated')
  return parser

def main(argv):
  parser = make_parser()
  args = parser.parse_args(argv)

  if args.hex_version:
    print(do_hex_version(args.hex_version))
  if args.guess_file_types:
    guesses = [guess_file_type(Path(p)) + ',' for p in args.guess_file_types.split(';')]
    print(';'.join(guesses))

if __name__ == '__main__':
  main(sys.argv[1:])

