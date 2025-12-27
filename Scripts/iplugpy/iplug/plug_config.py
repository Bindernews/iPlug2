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

from pathlib import Path
from datetime import datetime
import yaml
import sys
import json
import re
from typing import Any

NON_NAME_PATTERN = re.compile(r'[^A-Za-z0-9_]')
REG_C_NAME = re.compile(r"[a-zA-Z_][a-zA-Z0-9_]+", re.ASCII)
REG_CHANNEL_IO = re.compile(r"([0-9]+)-([0-9]+)", re.ASCII)

# List of valid plugin categories, sourced from CLAP's plugin-features.h
IPLUG_VALID_PLUGIN_CATEGORIES = [
  # Main categories
  "instrument", "audio-effect", "note-effect", "note-detector", "analyzer",
  # Sub-categories - instrument
  "synthesizer", "sampler", "drum", "drum-machine",
  # Sub-categories - audio effect
  "filter", "phaser", "equalizer", "de-esser", "phase-vocoder", "granular", "frequency-shifter", "pitch-shifter",
  "distortion", "transient-shaper", "compressor", "expander", "gate", "limiter",
  "flanger", "chorus", "delay", "reverb", "tremolo", "glitch",
  # Sub-categories - misc
  "utility", "pitch-correction", "restoration",
  "multi-effects"
  "mixing", "mastering",
]

VST3_CATEGORY_MAPPING = {
  "instrument":         "Instrument",
  "synthesizer":        "Instrument|Synth",
  "sampler":            "Instrument|Sampler",
  "drum":               "Instrument|Drum",
  "drum-machine":       "Instrument|DrumMachine",
  "audio-effect":       "Fx",
  "note-effect":        "Fx|Midi",
  "note-detector":      "Fx|Midi",
  "analyzer":           "Fx|Analyzer",
  "filter":             "Fx|Filter",
  "phaser":             "Fx|Phaser",
  "equalizer":          "Fx|Equalizer",
  "de-esser":           "Fx|DeEsser",
  "granular":           "Fx|Granular",
  "compressor":         "Fx|Compressor",
  "expander":           "Fx|Expander",
  "gate":               "Fx|Gate",
  "limiter":            "Fx|Limiter",
  "flanger":            "Fx|Flanger",
  "chorus":             "Fx|Chorus",
  "delay":              "Fx|Delay",
  "reverb":             "Fx|Reverb",
  "tremolo":            "Fx|Tremolo",
  "glitch":             "Fx|Glitch",
  "distortion":         "Fx|Distortion",
  "phase-vocoder":      "Fx|PhaseVocoder",
  "frequency-shifter":  "Fx|FrequencyShifter",
  "pitch-shifter":      "Fx|PitchShifter",
  "transient-shaper":   "Fx|TransientShaper",
  "utility":            "Misc|Utility",
  "pitch-correction":   "Misc|PitchCorrection",
  "restoration":        "Misc|Restoration",
  "multi-effects":      "Misc|MultiEffects",
  "mixing":             "Misc|Mixing",
  "mastering":          "Misc|Mastering",
}

LV2_CATEGORY_MAPPING = {
  "instrument":         "lv2:InstrumentPlugin",
  "synthesizer":        "lv2:GeneratorPlugin",
  "sampler":            "lv2:InstrumentPlugin",
  "drum":               "lv2:InstrumentPlugin",
  "drum-machine":       "lv2:InstrumentPlugin",
  "audio-effect":       "lv2:ModulatorPlugin",
  "note-effect":        "lv2:MIDIPlugin",
  "note-detector":      "lv2:MIDIPlugin",
  "analyzer":           "lv2:AnalyzerPlugin",
  "filter":             "lv2:FilterPlugin",
  "phaser":             "lv2:PhaserPlugin",
  "equalizer":          "lv2:EQPlugin",
  "de-esser":           "lv2:FilterPlugin",
  "granular":           "lv2:FilterPlugin",
  "compressor":         "lv2:CompressorPlugin",
  "expander":           "lv2:ExpanderPlugin",
  "gate":               "lv2:GatePlugin",
  "limiter":            "lv2:LimiterPlugin",
  "flanger":            "lv2:FlangerPlugin",
  "chorus":             "lv2:ChorusPlugin",
  "delay":              "lv2:DelayPlugin",
  "reverb":             "lv2:ReverbPlugin",
  "tremolo":            "lv2:DistortionPlugin",
  "glitch":             "lv2:DistortionPlugin",
  "distortion":         "lv2:DistortionPlugin",
  "phase-vocoder":      "lv2:ModulatorPlugin",
  "frequency-shifter":  "lv2:PitchPlugin",
  "pitch-shifter":      "lv2:PitchPlugin",
  "transient-shaper":   "lv2:EnvelopePlugin",
  "utility":            "lv2:UtilityPlugin",
  "pitch-correction":   "lv2:PitchPlugin",
  "restoration":        "lv2:UtilityPlugin",
  "multi-effects":      "lv2:Plugin",
  "mixing":             "lv2:MixerPlugin",
  "mastering":          "lv2:MixerPlugin",
}

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

def version_to_hex(ver: 'list[int]') -> 'str':
  # Use two hex digits for major version, and ignore tweak.
  # This is because many orgs are using the year as the major version now.
  return f'0x{ver[0]:04x}{ver[1]:02x}{ver[2]:02x}'

def version_to_commas(ver: 'list[int]') -> 'str':
  return ','.join([str(x) for x in ver[0:4]])

def do_hex_version(s: str):
  ver = parse_version(s)
  print(version_to_hex(ver))

def lowercase_keys(d: 'dict') -> 'dict':
  """Return a new dictionary where all the keys are lower-cased strings."""
  return {str(k).lower(): v for k,v in d.items()}

def normalize_channel_io(inp: 'list[str]|str') -> 'list[str]':
  if not isinstance(inp, str):
    raw_str = ' '.join(inp)
  else:
    raw_str = inp
  parts = filter(lambda s: s!='', raw_str.split(' '))
  result = []
  for io_setup in parts:
    if not REG_CHANNEL_IO.fullmatch(io_setup):
      raise ValueError(f'Invalid channel IO "{io_setup}"')
    result.append(io_setup)
  return result

def check_gui_backend(g_back:str, name: str, auto_val: str, choices: 'list[str]') -> str:
  """Check that the selections for the GUI backend are a valid configuration.

  :param g_back: User-input backend
  :param name: Library name (e.g. Skia, NanoVG)
  :param auto_val: Backend to use if ``g_back`` is "auto"
  :param choices: List of valid backends
  :returns: A valid ``g_back``
  """
  if g_back == 'auto':
    g_back = auto_val
  if not g_back in choices:
    choices_str = ', '.join(choices)
    raise ValueError(f'Invalid backend for {name} "{g_back}" - choices are {choices_str}')
  return g_back

def parse_graphics_api(api: str) -> 'tuple[str, str]':
  # Parse UI backend options
  m = re.match(r"([a-z]+)([+](gl2|gl3|cpu|auto))?", api.lower())
  if m:
    g_lib = m.group(1)
    g_back = m.group(3) or 'auto'
  else:
    g_lib = ''
    g_back = ''
    
  if g_lib == 'nanovg':
    g_back = check_gui_backend(g_back, 'NanoVG', 'gl2', ['auto', 'gl2', 'gl3'])
  elif g_lib == 'skia':
    g_back = check_gui_backend(g_back, 'Skia', 'cpu', ['auto', 'gl2', 'gl3', 'cpu'])
  elif g_lib == 'custom':
    g_back = check_gui_backend(g_back, 'Custom', 'auto', ['auto'])
  elif g_lib == 'none':
    g_back = 'cpu'
  else:
    raise ValueError(f"Invalid IGraphics library {g_lib} - choices are NanoVG, Skia, Custom, None")
  
  return (g_lib, g_back)


def build_full_config(config_in: dict, defaults: dict) -> dict:
  """Build a fully valid dictionary containing config fields.
  See IPlugFunctions.cmake for details on the config fields.
  """
  meta = dict()
  # Helper function to determine the final value for a key
  def update_key(k: str, *args, as_bool = False, as_int = False):
    choices = [config_in.get(k), defaults.get(k)]
    choices.extend(args)
    # Choose first not-empty (!= None and != '') value, default to last value
    v: Any = next((x for x in choices if x is not None and x != ''), choices[-1])
    # Convert booleans into 1/0
    if as_bool:
      v = 1 if v else 0
    elif as_int:
      try:
        v = int(v)
      except ValueError:
        raise ValueError(f"Config key \"{k}\" must be an integer")
    # Update meta
    meta[k] = v

  # Parse graphics options. 
  graphics_api = defaults.get("graphics") or meta.get("graphics") or "nanovg+gl2"
  gui_library, gui_backend = parse_graphics_api(graphics_api)
  # Set these directly, user cannot override them
  meta["gui_library"] = gui_library
  meta["gui_backend"] = gui_backend
  has_ui = gui_library != 'none'
  meta["has_ui"] = int(has_ui)

  update_key("name", defaults["name"], None)
  update_key("class_name", defaults["name"], None)
  update_key("version", defaults["version"], "")
  update_key("year", datetime.now().year)
  update_key("description", defaults["description"], "")
  update_key("email", "spam@me.com")
  update_key("author", "")
  update_key("category", "")
  
  # Validate some fields
  plug_name = meta["name"]
  plug_class_name = meta["class_name"]
  plug_category = meta["category"]
  if plug_name is None:
    raise ValueError("Plugin name not set")
  if plug_class_name is None or not REG_C_NAME.fullmatch(plug_class_name):
    raise ValueError("Plugin class name is invalid")
  if plug_category != '' and not plug_category in IPLUG_VALID_PLUGIN_CATEGORIES:
    raise ValueError(f"Invalid plugin category: {plug_category}")
  
  # Channel IO is a special case as it can either be a list or a set of space-separated configs.
  # The final result is a list of space-separated configs, so we need to normalize and verify.
  channel_io = config_in.get("channel_io", "0-2")
  meta["channel_io"] = ' '.join(normalize_channel_io(channel_io))

  update_key("url", defaults["url"], "")
  update_key("manual_url", "")
  update_key("dev_language", "English")
  update_key("latency", 0, as_int=True)
  update_key("midi_in", False, as_bool=True)
  update_key("midi_out", False, as_bool=True)
  update_key("does_mpe", False, as_bool=True)
  update_key("allow_host_resize", False, as_bool=True)

  # These use values from meta[] in their defaults
  update_key("support_url", meta["url"], "")
  update_key("author_id", meta["author"][0:4], "")
  update_key("copyright", f'Copyright (c) {meta["year"]} {meta["author"]}'.strip())
  ver_list = parse_version(meta["version"])
  update_key("version_hex", version_to_hex(ver_list))
  update_key("version_commas", version_to_commas(ver_list))
  update_key("category_clap", plug_category, "")
  update_key("category_vst3", VST3_CATEGORY_MAPPING.get(plug_category), "")
  update_key("category_lv2", LV2_CATEGORY_MAPPING.get(plug_category), "")
  update_key("unique_id", "PmBl")
  update_key("ui_width", 800 if has_ui else 0, as_int=True)
  update_key("ui_height", 600 if has_ui else 0, as_int=True)
  update_key("ui_fps", 60 if has_ui else 0, as_int=True)
  
  # Currently we don't let the user override this
  meta["author_csafe"] = NON_NAME_PATTERN.sub('_', meta["author"])
  
  # Validate author id
  plug_author_id = meta["author_id"]
  if len(plug_author_id) != 4:
    print('WARNING: The author_id must be a 4-character ASCII string. Using "Test" as the fallback.', file=sys.stderr)
    meta["author_id"] = "Test"

  # Add in any extra fields from the input
  for k in config_in:
    if not k in meta:
      meta[k] = config_in[k]
  
  return meta

def cm_build_config(config_str: str, defaults: dict):
  # Load the raw config, and convert all keys to lowercase
  try:
    config_in = lowercase_keys(yaml.safe_load(config_str))
    print(json.dumps(build_full_config(config_in, defaults), sort_keys=True))
  except ValueError as e:
    print(f"ERROR: {e}", file=sys.stderr)
    exit(1)

