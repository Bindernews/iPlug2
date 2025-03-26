/*
 ==============================================================================
 
 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers. 
 
 See LICENSE.txt for  more info.
 
 ==============================================================================
*/

#ifndef _IPLUGAPI_
#define _IPLUGAPI_

#include "IPlugAPIBase.h"
#include "IPlugProcessor.h"

#include <lv2/core/lv2.h>
#include <lv2/core/lv2_util.h>
#include <lv2/atom/forge.h>
#include <lv2/urid/urid.h>
#include <lv2/ui/ui.h>
#include <unordered_map>
#include <heapbuf.h>
#include <string>

BEGIN_IPLUG_NAMESPACE


#ifndef PLUG_URI
#define PLUG_URI PLUG_URL_STR "/plugins/" PLUG_NAME
#endif

#ifndef PLUG_UI_URI
#define PLUG_UI_URI PLUG_URI "#ui"
#endif

#define LV2_IPLUG2_PREFIX "https://iplug2.github.io/lv2#"
#define LV2_IPLUG2__UIMessage  LV2_IPLUG2_PREFIX "UIMessage"
#define LV2_IPLUG2__msgTag  LV2_IPLUG2_PREFIX "msgTag"
#define LV2_IPLUG2__ctrlTag LV2_IPLUG2_PREFIX "ctrlTag"
#define LV2_IPLUG2__data    LV2_IPLUG2_PREFIX "data"
#define LV2_IPLUG2__InvalidInstance  LV2_IPLUG2_PREFIX "InvalidInstance"


/////////////////
// Common Code //
/////////////////

/**
 * Wraps an LV2_Atom_Forge that is used for building sequences.
 */
class AtomSequenceForge
{
public:
  AtomSequenceForge();
  ~AtomSequenceForge();

  inline operator LV2_Atom_Forge*() { return &forge; }

  void init(LV2_URID_Map *map);
  void open(LV2_Atom_Sequence *seq);
  void close();

  /** Convenience function for lv2_atom_forge_raw. */
  bool forge_raw(const void *data, uint32_t length);

  LV2_Atom_Forge forge;
  LV2_Atom_Forge_Frame sequence_head;
  bool used;
};

struct URIDMap
{
public:
  LV2_URID atom_atomTransfer;
  LV2_URID atom_Blank;
  LV2_URID atom_Chunk;
  LV2_URID atom_eventTransfer;
  LV2_URID atom_Object;
  LV2_URID atom_URID;
  LV2_URID atom_Float;
  LV2_URID atom_Bool;
  LV2_URID midi_MidiEvent;
  LV2_URID patch_Set;
  LV2_URID patch_property;
  LV2_URID patch_value;
  LV2_URID iplug2_ctrlTag;
  LV2_URID iplug2_data;
  LV2_URID iplug2_msgTag;
  LV2_URID iplug2_UIMessage;

  bool init(LV2_URID_Map *map, int nParams);

  int getParam(LV2_URID urid);
  LV2_URID get(const char *uri);

  inline LV2_URID_Map* map() const { return mMap; }

private:
  LV2_URID_Map *mMap;
  std::unordered_map<std::string, LV2_URID> mExtras;
  std::unordered_map<LV2_URID, int> mParamMap;
};


template<typename Impl>
class IPlugLV2Common
{
protected:

  bool HandleAtomPatchSet(const LV2_Atom_Object *obj, iplug::EParamSource source, uint32_t sampleAt)
  {
    auto self = static_cast<Impl*>(this);

    // Determine the Param index from property ID
    const LV2_Atom* property = nullptr;
    const LV2_Atom* val = nullptr;
    lv2_atom_object_get(obj,
        mURIs.patch_property, &property,
        mURIs.patch_value, &val,
        0);
    if (!property || !val)
    {
      return false;
    }

    LV2_URID paramUrid = reinterpret_cast<const LV2_Atom_URID*>(property)->body;
    float newValue = reinterpret_cast<const LV2_Atom_Float*>(val)->body;
    int paramId = mURIs.getParam(paramUrid);
    self->GetParam(paramId)->Set(newValue);
    self->OnParamChange(paramId, source, sampleAt);
    return true;
  }

  bool HandleAtomUIMessage(const LV2_Atom_Object *obj)
  {
    auto self = static_cast<Impl*>(this);

    LV2_Atom* atMsgTag = nullptr;
    LV2_Atom* atCtrlTag = nullptr;
    LV2_Atom* atMsgData = nullptr;
    if (lv2_atom_object_get(obj,
        mURIs.iplug2_msgTag, &atMsgTag,
        mURIs.iplug2_ctrlTag, &atCtrlTag,
        mURIs.iplug2_data, &atMsgData,
        0) != 3)
    {
      return false;
    }

    int msgTag = reinterpret_cast<LV2_Atom_Int*>(atMsgTag)->body;
    int ctrlTag = reinterpret_cast<LV2_Atom_Int*>(atCtrlTag)->body;
    const uint8_t *data_ptr = reinterpret_cast<uint8_t*>(atMsgData + sizeof(LV2_Atom));
    self->OnMessage(msgTag, ctrlTag, atMsgData->size, data_ptr);
    return true;
  }

  URIDMap mURIs;
};


/////////////////////
// END Common Code //
/////////////////////

#if IPLUG_DSP

/** Used to pass various instance info to the API class */
struct InstanceInfo
{
  const LV2_Descriptor *descriptor;
  double rate;
  const char* bundle_path;
  const LV2_Feature* const* features;
};

typedef LV2_Handle (*LV2_InstantiateFn)(const LV2_Descriptor *descriptor,
                                      double rate, const char* bundle_path,
                                      const LV2_Feature* const* features);

/**  LV2 processor base class for an IPlug plug-in
*   @ingroup APIClasses */
class IPlugLV2DSP : public IPlugAPIBase
                  , public IPlugProcessor
                  , public IPlugLV2Common<IPlugLV2DSP>
{
public:
  IPlugLV2DSP(const InstanceInfo& info, const Config& config);
  ~IPlugLV2DSP();

  /*
  //IPlugAPIBase
  void BeginInformHostOfParamChange(int idx) override;
  void InformHostOfParamChange(int idx, double normalizedValue) override;
  void EndInformHostOfParamChange(int idx) override;
  void InformHostOfProgramChange() override;
  void HostSpecificInit() override;
  bool EditorResizeFromDelegate(int viewWidth, int viewHeight) override;

  //IPlugProcessor
  void SetLatency(int samples) override;
  bool SendSysEx(const ISysEx& msg) override;
  */
  bool SendMidiMsg(const IMidiMsg& msg) override;

#if 0
  void SendControlValueFromDelegate(int ctrlTag, double normalizedValue) override;
  void SendControlMsgFromDelegate(int ctrlTag, int msgTag, int dataSize, const void* pData) override;
  void SendParameterValueFromDelegate(int paramIdx, double value, bool normalized) override {} // NOOP in VST3 processor -> param change gets there via IPlugVST3Controller::setParamNormalized
  void SendArbitraryMsgFromDelegate(int msgTag, int dataSize = 0, const void* pData = nullptr) override;
#endif

  // IPlugAPIBase
  virtual void SendMidiMsgFromUI(const IMidiMsg& msg) override;
  virtual void SendSysexMsgFromUI(const ISysEx& msg) override;
  virtual void SendArbitraryMsgFromUI(int msgTag, int ctrlTag, int dataSize, const void* pData) override;

  //LV2 methods
  void  connect_port(uint32_t port, void *data);
  void  activate();
  void  run(uint32_t n_samples);
  void  deactivate();

  static const LV2_Descriptor* descriptor(uint32_t index, LV2_InstantiateFn instantiate);
  
  int GetFirstControlPort() const;
  int write_manifest(const char* dest_dir);
  int write_also(const char* dest_dir);

private:
  int write_also_io(FILE* f, const IOConfig* io, int io_index);
  int write_cfg_parameters(FILE* f);
  int write_indent(FILE* f, int indent, const char* msg);

  WDL_TypedBuf<void*>  mPorts;
  WDL_TypedBuf<float*> mIOPorts;
  WDL_TypedBuf<float*> mControlPorts;
  URIDMap mURIs;
  /** Atom forge for control_out port (1) */
  AtomSequenceForge mForgeCtrl;
  LV2_URID_Map *mMap;
  bool mFirstActivate;
};

#endif

#if IPLUG_EDITOR
#include "xcbt.h"

/** Used to pass various instance info to the API class */
struct InstanceInfo
{
  const LV2UI_Descriptor* descriptor;
  const char* plugin_uri;
  const char* bundle_path;
  LV2UI_Write_Function write_function;
  LV2UI_Controller controller;
  const LV2_Feature* const* features;
};

/**  LV2 editor base class for an IPlug plug-in
*   @ingroup APIClasses */
class IPlugLV2Editor : public IPlugAPIBase
                     , public IPlugLV2Common<IPlugLV2Editor>
{
public:
  IPlugLV2Editor(const InstanceInfo& info, const Config& config);
  ~IPlugLV2Editor();

  //IPlugAPIBase
  void InformHostOfParamChange(int idx, double normalizedValue) override;
  /*
  void BeginInformHostOfParamChange(int idx) override;
  void EndInformHostOfParamChange(int idx) override;
  void InformHostOfProgramChange() override;
  bool EditorResizeFromDelegate(int viewWidth, int viewHeight) override;
  */
  
  LV2UI_Widget CreateUI(); // post constructor to create window

  //LV2 UI methods
  void port_event(uint32_t port_index, uint32_t buffer_size, uint32_t format, const void*  buffer);
  int  ui_idle();
  int  ui_resize(int w, int h);

  //IEditorDelegate
  bool EditorResizeFromUI(int viewWidth, int viewHeight, bool needsPlatformResize) override;
  
private:
  int mParameterPortOffset;

  LV2UI_Write_Function mHostWrite;
  LV2UI_Controller mHostController;
  LV2UI_Widget mHostWidget;
  LV2UI_Resize * mHostResize;
  URIDMap mURIs;
  bool mHostSupportIdle;
  
#ifdef OS_LINUX
  xcbt_embed * mEmbed;
#endif
};

#endif

END_IPLUG_NAMESPACE

#endif /* __IPLUGAPI_H */
