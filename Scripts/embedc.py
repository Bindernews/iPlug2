#!/usr/bin/env python3
#
# Copyright (c) 2025 Andrew "bindernews" Heintz
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
# documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# SPDX-License-Identifier: MIT

import argparse
import dataclasses
import hashlib
import json
import logging
import os
import posixpath
import re
import sys
from pathlib import Path
from typing import TextIO

# Logger for this program
logger = logging.getLogger(__name__)

NON_NAME_PATTERN = re.compile(r'[^A-Za-z0-9_]')
""" Regex matching invalid characters in C variable/type names """

NON_ESCAPED_EQUALS = re.compile(r'(?<!\\)=')
""" Regex to match a '=' without a preceeding \\ """

DATA_SUFFIX = '_data'
INC_STDINT = '#include <stdint.h>\n'

EXTERN_C_BEGIN = '''\
#ifdef __cplusplus
extern "C" {
#endif
'''

EXTERN_C_END = '''\
#ifdef __cplusplus
}
#endif
'''

STRUCT_DECL = '''\
#ifndef {0}
#define {0}
struct {1} {{ const char* name; const uint32_t size; const unsigned char* data; }};
#endif
'''

LOADER_FUNCTION_C = '''\
const void* {0}(const char *path, unsigned int *p_size)
{
  for (int i = 0; {1}[i].data; i++)
  {
    if (strcmp({1}[i].name, path) == 0)
    {
      *p_size = {1}[i].size;
      return {1}[i].data;
    }
  }
  *p_size = 0;
  return NULL;
}
'''

def make_cname(s):
  return re.sub(NON_NAME_PATTERN, '_', s)
  
def bytes_to_c_array(d: bytes):
  msg = []
  # Convert the bytes into a C array
  for i in range(len(d)):
    if i % 200 == 0:
      msg.append('\n')
    msg.append('%d,' % d[i])
  msg.append('\n')
  return ''.join(msg)

def bytes_to_c_string(d: bytes) -> str:
  """Convert a set of bytes to an escaped C string.
  
  The resulting string may be split across multiple lines
  using the fact that C compiler auto-concatenate adjacent strings
  (e.g. "Hello" " " "world!" is treated as "Hello world!").
  """
  msg = []
  for b in d:
    if b == 32: # safe space
      msg.append(' ')
    elif b == 34:
      msg.append('\\"')
    elif b == 37: # % can mess up string parsing
      msg.append('\\45')
    elif b == 63:
      msg.append('\\?')
    elif b == 92:
      msg.append(r'\\')
    elif (35 <= b and b <= 46) or (58 <= b and b <= 126):
      msg.append(chr(b))
    elif b < 34:
      msg.append('\\%o' % b)
    else:
      msg.append('\\%03o' % b)
  # Convert to multiple lines
  lines = []
  for i in range(0, len(msg), 200):
    line = ''.join(msg[i:i+200])
    lines.append(f'"{line}"\n')
  # Join the lines
  return ''.join(lines)


class UserError(Exception):
  pass

@dataclasses.dataclass
class FileEmbed:
  """Represends a file to be embedded in an executable.
  
  This may contain the actual data of the file, or not if it was read from an existing generated file.
  """

  name: str
  """ Effective file path, without quotes """
  cname: str
  """ Name of the C declaration for this struct """
  size: int
  """ Size of the data """
  data_name: str
  """ Name of the byte array containing the data """
  data: bytes|None = None
  """ The actual file contents (optional) """

  def write_data_c(self, fd: 'TextIO') -> None:
    """
    Write the data as a C array of uint8_t.
    """
    # Convert the bytes into a C array, with extra null character at the end.
    # This is both to terminate strings, so they can be used without copying, but also
    # ensures that the array is never zero-length since that's not allowed.
    # Also using quoted strings with embedded octal data seems faster for the compiler.
    d = self.data + bytes([0])
    fd.write(f'const unsigned char {self.data_name}[{len(d)}] = ')
    # fd.write('{' + bytes_to_c_array(d) + '};\n')
    fd.write('{\n' + bytes_to_c_string(d) + "};\n")

  def declaration(self) -> str:
    return f'{{ \"{self.name}\", {self.size}, {self.data_name} }}'
  
  @staticmethod
  def parse_declaration(decl: str) -> 'FileEmbed':
    # Double check that we're parsing a declaration
    if decl[0] != '{' or decl[-1] != '}' or decl.count(',') < 2:
      raise ValueError('invalid declaration')
    decl1 = decl[1:-2]
    # Find commas backwards because the file name MIGHT contain a comma.
    # We KNOW there are at least 2 commas, but one might be inside the name for an invalid declaration
    # so json.loads might fail.
    comma2 = decl1.rfind(',')
    comma1 = decl1.rfind(',', 0, comma2 - 1)
    data_name = decl1[comma2 + 1:].strip()
    size = int(decl1[comma1 + 1:comma2].strip())
    # Json string parsing is close enough to C for this, probably
    try:
      name = json.loads(decl1[0:comma1])
    except json.JSONDecodeError:
      raise ValueError('invalid declaration')
    # Assume this is true for now
    cname = data_name.removesuffix(DATA_SUFFIX)
    # Return parsed result
    return FileEmbed(name=name, cname=cname, size=size, data_name=data_name, data=None)
  
class InputSpec:
  """A parsed input specification.
  
  Input is in the form ``<path>`` or ``<embed_path>=<path>``, where ``<path>`` can be
  a direct path or a glob expression, and ``<embed_path>`` may be either a full path
  or a folder, but if it's a full path and ``<path>`` is a glob that produces multiple
  files, the program will produce a warning.

  :param embed_path: The embedded path for the file. If it ends in a "/" it's considered a folder.
  """

  def __init__(self, embed_path: str, path_str: str, files: 'list[Path]' = []):
    self.embed_path: str = embed_path
    """
    The embedded path for the file, or a folder if ``len(self.files) > 1``.
    Embed paths must use forward-slashes, and "folders" end with a "/".
    """
    self.path_str: str = path_str
    """ The original input that was used, may be a glob, relative path, etc. """
    self.files: 'list[Path]' = files
    """ List of resolved input files, may be only 1 if input is not a glob. """
  
  def is_folder(self) -> bool:
    """Check if the embed_path is considered a "folder"."""
    return self.embed_path == '' or self.embed_path.endswith('/')

  def __str__(self):
    if len(self.files) == 1:
      return f'{self.embed_path}={self.files[0]}'
    else:
      return f'{self.embed_path}={json.dumps(self.files)}'

  def resolve_files(self, cwd: Path):
    """
    Resolves ``self.path_str`` and ``cwd`` to a list of absolute file paths,
    updating ``self.files``.
    """

    # Fix the path so it's absolute
    if not Path(self.path_str).is_absolute():
      f_path = Path(cwd, self.path_str)
    else:
      f_path = Path(self.path_str)
    
    # Try to resolve it to a file
    if f_path.is_file():
      self.files.append(f_path)
      return
    if f_path.is_dir():
      # Cannot handle directories yet
      raise UserError(f'Cannot embed directories, please use globs - input: {f_path}')
    # Check if the path contains any glob characters, if not then it's invalid.
    if not InputSpec.maybe_glob(str(f_path)):
      raise UserError(f'Cannot find file(s) - input: {f_path}')
    # Try to resolve as a glob. Globs must be relative, so make it "relative" to the anchor
    for p in Path(f_path.anchor).glob('/'.join(f_path.parts[1:])):
      self.files.append(p)
    if len(self.files) == 0:
      logger.warning('msg="input spec did not match any files" spec="%s"', self.path_str)

  @staticmethod
  def flatten(specs: 'list[InputSpec]', absolute: bool = False) -> 'list[InputSpec]':
    """
    Take a list of `InputSpec`s that may have more than one file, and return
    a list where each only has one file, and the embed_path is set correctly
    based on if the input spec embed_path is a folder or not.

    :param specs: List of input specs to flatten
    :param absolute: If true resolve the output paths to be absolute, and follow any symlinks, otherwise don't
    """
    result = []
    for in0 in specs:
      # Check that multi-file specs are "folders"
      is_folder = in0.is_folder()
      if len(in0.files) > 1 and not is_folder:
        # Assume embed_path is a folder
        raise ValueError(f"Cannot flatten input spec with absolute embed path and multiple files - input: {in0.path_str}")
      # Make one spec for each individual file, copying the embed_path
      for path in in0.files:
        ep = in0.embed_path
        if is_folder:
          ep += path.name
        path2 = path.resolve() if absolute else path
        result.append(InputSpec(embed_path=ep, path_str=in0.path_str, files=[path2]))
    # Return the result
    return result

  @staticmethod
  def maybe_glob(s: str) -> bool:
    """Return true if ``s`` might be a glob pattern, false if it definitely is not."""
    return '*' in s or '?' in s or ('[' in s and ']' in s)

  @staticmethod
  def parse(input: 'str|Path|InputSpec', cwd: 'Path|None' = None, default_dir: str = '') -> 'InputSpec':
    """Parse an input specification. See :ref:`InputSpec` for details.

    If ``cwd`` is not `None`, then this will also call ``resolve_files()`` before returning the instance.
    
    :param input: The input string to parse
    :param cwd: Path acting as the "current directory" for relative paths, or `None` to not resolve
    :returns: New `InputSpec` object
    """

    if isinstance(input, InputSpec):
      return InputSpec(embed_path=input.embed_path, path_str=input.path_str, files=list(input.files))

    if isinstance(input, Path):
      embed_path = None
      path_str = str(input)
    else:
      # Split on = sign
      ar = NON_ESCAPED_EQUALS.split(input, 1)
      if len(ar) == 1:
        embed_path = None
        path_str = ar[0]
      else:
        embed_path = ar[0]
        path_str = ar[1]
    
    # Make a reasonable embed_path, but don't guess.
    # Either it's provided, or just assume file at the root.
    if embed_path is None:
      embed_path = default_dir
    embed_path = embed_path.lstrip('/')

    spec = InputSpec(embed_path=embed_path, path_str=path_str, files=[])
    if cwd is not None:
      spec.resolve_files(cwd)
    return spec
  
  @staticmethod
  def parse_all(inputs: 'list[str]', cwd: 'Path|None' = None, default_dir: str = '') -> 'list[InputSpec]':
    return [InputSpec.parse(s, cwd, default_dir) for s in inputs]

class EmbedHelper:
  """ Helper for various embedc operations. """

  # Class variables
  SCALED_FILE_PATTERN = re.compile(r'@[0-9]x?$')
  """ Regex matching "scaled" file suffix """

  def __init__(self):
    self.resource_type = 'embedded_file'
    """ The name of the "file entry" struct type """
    self.entry_prefix = 'embed_'
    """ Prefix for embedded_file variable names """
    self.array_name = 'EMBED_LIST'
    """ The name of the embedded_file array containing all entries """
    self.load_function = 'load_embedded_file'
    """ The name of the function to locate an embedded file """
    self.cwd = Path('.').resolve()
    """ Current working directory """
    self.file_list: 'list[FileEmbed]' = []
    """ List of files to embed """
    self.indent = '  '
    """ Indentation string """
    self.default_embed_directory: str = ''
    """ Default directory to place embedded files, does not override explicit locations. """
    self.scaled_file_types = ['.png']
    """ bin2c will search for higher-resolution copies of files with these extensions """

  def write_header(self, fd: 'TextIO'):
    # Guard for multiple headers defining resource_t
    guard_def = self.resource_type.upper() + '_DEFINED'
    # Include stdint.h
    fd.write(INC_STDINT)
    # Define resource_t in case we need it
    fd.write(STRUCT_DECL.format(guard_def, self.resource_type))
    fd.write('\n')

  def write_data_file(self, fd: 'TextIO'):
    """
    Generate a C file containing byte arrays of file entries.

    :param fd: File-like object to write to
    """
    # Process each entry
    for en in self.file_list:
      en.write_data_c(fd)
      fd.write(f'const struct {self.resource_type} {en.cname} = {en.declaration()};\n')

  def write_list(self, fd: 'TextIO', extern=True):
    """
    Write an array of embedded_file entries that contain all known embedded files.

    :param fd: Output, a file-like object
    :param extern: If true, add "extern" declarations for the data fields, otherwise
      assume they're already declared (e.g. --convert and --bundle)
    """
    msg = []
    if extern:
      for e in self.file_list:
        msg.append(f'extern const unsigned char {e.data_name}[{e.size}];\n')
    msg.append('\n\n')
    msg.append(f'const struct {self.resource_type} {self.array_name}[] = {{\n')
    for e in self.file_list:
      msg.append(f'{self.indent}{e.declaration()},\n')
    # Empty value indicates end of the array
    msg.append(self.indent + '{ NULL, 0, NULL },\n')
    msg.append('};\n\n')
    fd.write(''.join(msg))

  def write_list_header(self, fd: 'TextIO'):
    fd.write('#pragma once\n')
    fd.write(EXTERN_C_BEGIN)
    self.write_header(fd)
    fd.write(f'extern const {self.resource_type} *{self.array_name};\n')
    fd.write(f'const void* {self.load_function}(const char *path, unsigned int *p_size);\n')
    fd.write(EXTERN_C_END)
    fd.write('\n')

  def parse_all_inputs(self, inputs: 'list[str]') -> 'list[InputSpec]':
    return InputSpec.parse_all(inputs, self.cwd, default_dir=self.default_embed_directory)

  def load_inputs_for_convert(self, inputs: 'list[str]') -> 'list[FileEmbed]':
    specs = self.resolve_input_specs(self.parse_all_inputs(inputs))
    return self.make_embeds_from_files(specs)
  
  def load_inputs_for_bundle(self, inputs: 'list[str]') -> 'list[FileEmbed]':
    specs = InputSpec.flatten(self.parse_all_inputs(inputs), absolute=True)
    return self.scan_data_files([p.files[0] for p in specs])
  
  def load_inputs_for_show(self, inputs: 'list[str]') -> 'list[InputSpec]':
    return self.resolve_input_specs(self.parse_all_inputs(inputs))
  

  def handle_cli(self, args: 'HelperCliArgs'):
    # Set self options from CLI arguments
    if args.C:
      self.cwd = Path(args.C).resolve()
    if args.type:
      self.resource_type = args.type
    if args.array:
      self.array_name = args.array
    if args.scaled:
      self.scaled_file_types = args.scaled.split(',')
    if args.into:
      self.default_embed_directory = args.into

    if args.convert:
      # Convert and possibly bundle
      self.file_list = self.load_inputs_for_convert(args.inputs)
      with args.output as fd:
        self.write_header(fd)
        self.write_data_file(fd)
        # If convert and bundle in one, then append here
        if args.bundle:
          self.write_list(fd, extern=False)

    elif args.bundle:
      # Bundle existing converted files, but NOT converting any new ones
      self.file_list = self.load_inputs_for_bundle(args.inputs)
      with args.output as fd:
        self.write_header(fd)
        self.write_list(fd, extern=True)

    elif args.show:
      # Parse inputs and then list them to the output
      specs = self.load_inputs_for_show(args.inputs)
      msg = [str(e) for e in specs]
      args.output.write('\n'.join(msg))

    if args.bundle and args.header:
      # Do this regardless of the value of args.convert or args.show
      with open(args.header, 'w') as fd:
        self.write_list_header(fd)

  def scan_data_files(self, files: 'list[os.PathLike]') -> 'list[FileEmbed]':
    """
    Scan generated data files, looking for embedded file resources. Returns a list of the C names for the embedded_file declarations.

    :param files: File(s) to scan
    :returns: A list of the C names for the embedded_file declarations
    """
    scan_reg = re.compile(f'const struct {self.resource_type} ({self.entry_prefix}[A-Za-z_0-9]*) = ([^;]+);')

    results = []
    for file in files:
      content = Path(file).read_text()
      for m in scan_reg.finditer(content):
        # Parse the declaration
        embed = FileEmbed.parse_declaration(m.group(2))
        # Force-set the cname, even though it's probably guessable from the data name
        embed.cname = m.group(1)
        # Append to results
        results.append(embed)
    return results
  
  def resolve_input_specs(self, specs: 'list[InputSpec]') -> 'list[InputSpec]':
    """Resolve input specs with additional files, and return a flattened list."""
    if len(self.scaled_file_types) > 0:
      # For each input, try to find alternate files.
      for in0 in specs:
        alt_files = self.find_alternate_files(in0.files)
        # Combine old results and new, removing duplicates
        in0.files = list(set(in0.files).union(alt_files))
    # flatten input paths
    return InputSpec.flatten(specs, absolute=True)
  
  def find_alternate_files(self, paths: 'list[Path]') -> 'list[Path]':
    """
    Returns a list of paths similar to the input paths but with an "@[1-9]" suffix
    after the base file name but before the extension.
    """    
    result = []
    for p0 in paths:
      # Only search for suffixes that we care about, and ignore any files
      # we've found that already have a scaled suffix, because presumably we got
      # the base version as well.
      if not p0.suffix in self.scaled_file_types or self.SCALED_FILE_PATTERN.match(p0.stem):
        continue
      pattern = p0.stem + '@*' + p0.suffix
      result.extend(p0.parent.glob(pattern))
    return result

  def make_embeds_from_files(self, inputs: 'list[InputSpec]') -> 'list[FileEmbed]':
    """
    Create entry objects from the given path(s) or input specs.
    This will read file contents, compress data as requested, and then generate entries.

    :param inputs: The input path(s) or pre-parsed input spec objects, must be "flattened" before calling
    """
    # Process each flattened input
    result = []
    for spec in inputs:
      path = spec.files[0]

      # Read file contents
      data_in = path.read_bytes()

      # Generate a hash for the data so we can make a name.
      # We could use file names, but there is a much higher collision possibility.
      # This also means that we guarantee the main file list changes when a resource changes.
      h = hashlib.sha1()
      h.update(data_in)
      sha1_digest = h.digest().hex()
      cname = make_cname(self.entry_prefix + sha1_digest)
      name = posixpath.normpath(spec.embed_path)

      logger.info('msg="embedding file" path="%s" file="%s" sha1="%s"', name, path, sha1_digest)
      result.append(FileEmbed(
        name=name,
        cname=cname,
        data_name=cname + DATA_SUFFIX,
        size=len(data_in),
        data=data_in
      ))
    return result
  
@dataclasses.dataclass
class HelperCliArgs:
  """Typed representation of the cli parser options."""

  bundle: bool = False
  convert: bool = False
  show: bool = False

  header: 'Path|None' = None
  array: 'str|None' = None
  scaled: 'str|None' = None
  C: 'str|None' = None
  into: 'str|None' = None
  type: 'str|None' = None
  verbose: int = 0
  output: 'TextIO' = None
  inputs: 'list[str]' = None

def make_parser(prog: str = 'embedc.py') -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser(prog=prog)
  
  g_bundle = parser.add_argument_group('bundle options')
  g_bundle.add_argument('--bundle', action='store_true', help="""
  Bundle one or more C data files into a single list. If this option is given
  along with --convert then the files will be converted and bundled together.
  Otherwise the inputs are assumed to be existing C files that were produced
  as the output of --convert, and they will be scanned for embeds.  
  """)
  g_bundle.add_argument('--header', type=Path, help='Output header file which will contain the list declaration.')
  g_bundle.add_argument('--array', type=str, help='Name of the list. (default: EMBED_LIST)')

  g_convert = parser.add_argument_group('convert options')
  g_convert.add_argument('--convert', action='store_true', help='Convert one or more resource files into C data files.')
  g_convert.add_argument('-s', '--scaled', type=str, help='''
  Comma-separated list of extensions that bin2c should search for higher-resolution
  copies of (e.g. icon_20pt.png and icon_20pt@2x.png)
  ''') 

  g_find = parser.add_argument_group('show options')
  g_find.add_argument('--show', action='store_true', help='Print the files located and their embed paths')

  parser.add_argument('-C', type=str, default='.', metavar='<working directory>', help='Perform operations from the given directory.')
  parser.add_argument('--into', type=str, help='Set the sub-directory to put embed files into.')
  parser.add_argument('--type', type=str, help='Override the struct type name. (default: embedded_file)')
  parser.add_argument('-o', '--output', type=argparse.FileType('w'), default='-', required=True, help='Output file. (default: stdout)')
  parser.add_argument('-v', '--verbose', action='count', default=0, help='Increase the amount of log output.')

  INPUTS_HELP = '''
  Files to convert/bundle, in the format "<path>" or "<embed_path>=<path>".
  <path> may be a glob expression, an absolute path, or a relative path.
  If <path> is a glob expression and <embed_path> is set, then <embed_path>
  is treated as a folder and all matched files will be placed in that folder.
  This does NOT use relative pathing, so an input of "fonts/=**/*.ttf" will put
  ALL .ttf file in the "fonts/" embedded folder, regardless of location.
  '''
  parser.add_argument('inputs', type=str, nargs='*', default=[], help=INPUTS_HELP)
  return parser

def main(argv):
  parser = make_parser()
  args = parser.parse_args(argv[1:], HelperCliArgs())

  if not (args.convert or args.bundle or args.show):
    parser.error('at least one of --convert, --bundle, or --show is required')

  try:
    # Setup logger
    log_level = max(0, logging.WARNING - (10 * args.verbose))
    logger.setLevel(log_level)

    # Handle CLI operations
    b2 = EmbedHelper()
    b2.handle_cli(args)
  except UserError as e:
    logger.error(str(e))

if __name__ == '__main__':
  main(sys.argv)
