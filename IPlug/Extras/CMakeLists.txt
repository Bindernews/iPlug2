cmake_minimum_required(VERSION 3.20)

set(sdk ${CMAKE_CURRENT_LIST_DIR})

add_library(iPlug2_Faust INTERFACE)
iplug_target_add(iPlug2_Faust INTERFACE
  INCLUDE ${sdk}/Faust "${FAUST_INCLUDE_DIR}"
)

add_library(iPlug2_FaustGen INTERFACE)
iplug_target_add(iPlug2_FaustGen INTERFACE
  SOURCE ${sdk}/Faust/IPlugFaustGen.cpp
  LINK iPlug2_Faust
)
iplug_source_tree(iPlug2_FaustGen)

add_library(iPlug2_HIIR INTERFACE)
iplug_target_add(iPlug2_HIIR INTERFACE
  INCLUDE ${sdk}/HIIR
  SOURCE ${sdk}/HIIR/PolyphaseIIR2Designer.cpp
)
iplug_source_tree(iPlug2_HIIR)

add_library(iPlug2_OSC INTERFACE)
iplug_target_add(iPlug2_OSC INTERFACE
  INCLUDE ${sdk}/OSC
  SOURCE ${sdk}/OSC/IPlugOSC_msg.cpp
)
iplug_source_tree(iPlug2_OSC)

add_library(iPlug2_Synth INTERFACE)
set(cwd ${sdk}/Synth)
iplug_target_add(iPlug2_Synth INTERFACE
  INCLUDE ${cwd}
  SOURCE
    "${cwd}/ControlRamp.h"
    "${cwd}/MidiSynth.cpp"
    "${cwd}/MidiSynth.h"
    "${cwd}/SynthVoice.h"
    "${cwd}/VoiceAllocator.cpp"
    "${cwd}/VoiceAllocator.h"
)
iplug_source_tree(iPlug2_Synth)
