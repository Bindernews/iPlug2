/*
 ==============================================================================
 
 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers. 
 
 See LICENSE.txt for  more info.
 
 ==============================================================================
*/
#include "IPlugLV2.h"
#include "config.h"

#include <lv2/atom/atom.h>
#include <lv2/atom/forge.h>
#include <lv2/buf-size/buf-size.h>
#include <lv2/midi/midi.h>
#include <lv2/options/options.h>
#include <lv2/patch/patch.h>
#include <lv2/state/state.h>
#include <lv2/worker/worker.h>
#include <lv2/patch/patch.h>

#define NOTIMP printf("%s: not implemented\n", __FUNCTION__);
// Maximum number of DIGITS for IO configs (e.g. 9999 = 4 digits)
#define MAX_CONFIG_DIGITS (4) 

template<typename T, class Compare>
int binary_find(const T* ar, size_t len, const T* test, Compare comp)
{
  size_t lo = 0;
  size_t hi = len - 1;
  while (lo <= hi)
  {
    size_t mid = lo + ((hi - lo) / 2);
    int r = comp(ar + mid, test);
    if (r < 0)
      lo = mid + 1;
    else if (r > 0)
      hi = mid - 1;
    else
      return mid;
  }
  return -(int)hi;
}

BEGIN_IPLUG_NAMESPACE

#ifdef IPLUG_DSP

IPlugLV2DSP::IPlugLV2DSP(const InstanceInfo &info, const Config& config)
  : IPlugAPIBase(config, kAPILV2)
  , IPlugProcessor(config, kAPILV2)
  , mFirstActivate(true)
{
  // maybe: info.descriptor should match our expectation, should we check that?
 
  Trace(TRACELOC, "%s", config.pluginName);
  
  int nInputs = MaxNChannels(ERoute::kInput);
  int nOutputs = MaxNChannels(ERoute::kOutput);
  int nParams = NParams();
  // Allocate port pointers
  mPorts.Resize(2);
  mIOPorts.Resize(nInputs + nOutputs);
  mControlPorts.Resize(nParams);
  
  SetSampleRate(info.rate);
  
  int block_size = DEFAULT_BLOCK_SIZE; // that can lead to allocation in RT, but there is no workaround in case host does not specify it
  
  LV2_URID_Map *urid_map = nullptr;
  //LV2_URID_Unmap *urid_unmap = nullptr;
  const LV2_Options_Option *options = nullptr;
  auto features = info.features;
  if (features)
  {
    const LV2_Feature *feature;
    while((feature = *features++))
    {
      if(!strcmp(feature->URI, LV2_OPTIONS__options))
      {
        options = (const LV2_Options_Option *)feature->data;
      } else if(!strcmp(feature->URI, LV2_URID__map))
      {
        urid_map = (LV2_URID_Map *)feature->data;
      } else if(!strcmp(feature->URI, LV2_URID__unmap))
      {
        // urid_unmap = (LV2_URID_Unmap *)feature->data;
      }
    }
  }
  
  if(options && urid_map) // options we are looking for are URID based
  {
    LV2_URID maxBlockLengthID = urid_map->map(urid_map->handle, LV2_BUF_SIZE__maxBlockLength);
    // maybe: sequenceSize
    for(; options->key ; ++options)
    {
      if((options->key == maxBlockLengthID) && (options->size == sizeof(int) && options->value))
      {
        block_size =  *(int *)options->value; // at least Arodour reports theoretical maximum here, not currently used buffer size
      }
    }
  }

  if (urid_map)
  {
    // Find-Replace regex to turn name into full line
    // ([a-z]+)_([A-Za-z]+)   mCoreURIs.$1_$2 = GET_URID(LV2_\U$1 __$2);
#define GET_URID(name) urid_map->map(urid_map->handle, name)
    mCoreURIs.atom_Blank     = GET_URID(LV2_ATOM__Blank);
    mCoreURIs.atom_Object    = GET_URID(LV2_ATOM__Object);
    mCoreURIs.atom_URID      = GET_URID(LV2_ATOM__URID);
    mCoreURIs.atom_Float     = GET_URID(LV2_ATOM__Float);
    mCoreURIs.atom_Bool      = GET_URID(LV2_ATOM__Bool);
    mCoreURIs.midi_MidiEvent = GET_URID(LV2_MIDI__MidiEvent);
    mCoreURIs.patch_Set      = GET_URID(LV2_PATCH__Set);
    mCoreURIs.patch_property = GET_URID(LV2_PATCH__property);
    mCoreURIs.patch_value    = GET_URID(LV2_PATCH__value);

    // Map all params to URIDs
    WDL_String uri;
    int nParams = NParams();
    for (int n = 0; n < nParams; n++)
    {
      uri.SetFormatted(2048, "%s#Par%d", PLUG_URI, n);
      mParamIDMap[GET_URID(uri.Get())] = n;
    }
#undef GET_URID
  }

  SetBlockSize(block_size);

  // Default everything to connected, maybe: support less inputs/outpus then max (with separate descriptor, like Mono/Stereo/Surround 
  SetChannelConnections(ERoute::kInput, 0, nInputs, true);
  SetChannelConnections(ERoute::kOutput, 0, nOutputs, true);
  
  // TODO: CreateTimer();
}

IPlugLV2DSP::~IPlugLV2DSP()
{
}

// Private methods


//IPlugProcessor
bool IPlugLV2DSP::SendMidiMsg(const IMidiMsg& msg)
{
  LV2_Atom_Sequence* out_port = ((LV2_Atom_Sequence*)(mPorts.Get()[1]));

  struct MIDINoteEvent
  {
    LV2_Atom_Event event;
    uint8_t        msg[3];
  };

  MIDINoteEvent ev;
  ev.event.time.frames = msg.mOffset;
  ev.event.body.type = mCoreURIs.midi_MidiEvent;
  ev.event.body.size = 3;
  ev.msg[0] = msg.mStatus;
  ev.msg[1] = msg.mData1;
  ev.msg[2] = msg.mData2;
  lv2_atom_sequence_append_event(out_port, out_port->atom.size, &ev.event);

  return true;
}


//LV2 methods

void IPlugLV2DSP::connect_port(uint32_t port, void *data)
{
  // maybe : check the size
  if (port < mPorts.GetSize()) {
    mPorts.Get()[port] = data;
    return;
  }
  port -= mPorts.GetSize();
  if (port < mIOPorts.GetSize()) {
    mIOPorts.Get()[port] = (float*)data;
    return;
  }
  port -= mIOPorts.GetSize();
  if (port < mControlPorts.GetSize()) {
    mControlPorts.Get()[port] = (float*)data;
    return;
  }
}

void IPlugLV2DSP::activate()
{
  if (mFirstActivate) {
    mFirstActivate = false;
    int nParams = NParams();
    for (int i = 0; i < nParams; i++) {
      OnParamChange(i, kReset);
    }
  }
  OnActivate(true);
  OnReset();
}

void IPlugLV2DSP::run(uint32_t n_samples)
{
  int nInputs = MaxNChannels(ERoute::kInput);
  int nOutputs = MaxNChannels(ERoute::kOutput);
  int nParams = NParams();

  if(GetBlockSize() < n_samples)
  {
    // if host has no maxBlockLength, we can get there. Strictly speaking we violate hardRT by allocation,
    // but what else can we do in such case? Make the feature "required" and so do not support this host at all? 
    SetBlockSize(n_samples);
  }

  void** ports = mPorts.Get();
  //float **inPorts = (float **)(&ports[2]);
  //float **outPorts = (float **)(float **)(&ports[2 + nInputs]);
  float **inPorts = mIOPorts.Get();
  float **outPorts = mIOPorts.Get() + nInputs;

  AttachBuffers(ERoute::kInput, 0, nInputs, inPorts, n_samples);
  AttachBuffers(ERoute::kOutput, 0, nOutputs, outPorts, n_samples);

  LV2_ATOM_SEQUENCE_FOREACH(static_cast<LV2_Atom_Sequence*>(ports[0]), ev)
  {
    uint32_t atom_type = ev->body.type;

    if (atom_type == mCoreURIs.atom_Object)
    {
      const LV2_Atom_Object* obj = (LV2_Atom_Object*)&ev->body;
      if (obj->body.otype == mCoreURIs.patch_Set)
      {
        uint32_t sampleAt = ev->time.frames;
        // We should check to make sure bad hosts don't do this.
        // If so, report to host.
        if (sampleAt >= n_samples)
        {
          sampleAt = n_samples - 1;
        }

        // Determine the Param index from property ID
        const LV2_Atom* property = nullptr;
        lv2_atom_object_get(obj, mCoreURIs.patch_property, &property, 0);
        if (!property || property->type != mCoreURIs.atom_URID)
        {
          continue;
        }

        const LV2_Atom* val = nullptr;
        lv2_atom_object_get(obj, mCoreURIs.patch_value, &val, 0);
        if (!val)
        {
          continue;
        }

        LV2_URID urid = ((LV2_Atom_URID*)property)->body;
        OnParamChange(mParamIDMap[urid], EParamSource::kHost, sampleAt);
      }
    }
    
    if (atom_type == mCoreURIs.midi_MidiEvent)
    {
      const uint8_t* const msg = (const uint8_t*)(ev + 1);
      switch (lv2_midi_message_type(msg))
      {
      case LV2_MIDI_MSG_NOTE_ON:
      case LV2_MIDI_MSG_NOTE_OFF:
        ProcessMidiMsg(IMidiMsg((int)(ev->time.frames), msg[0], msg[1], msg[2]));
        break;
      // TODO finish switch-case for processing MIDI messages
      }
    }
  }
  // END LV2_ATOM_SEQUENCE_FOREACH
       
#ifdef LV2_CONTROL_PORTS
  ENTER_PARAMS_MUTEX;
  for (int i = 0; i < nParams; ++i)
  {
    float *pParam = mControlPorts.Get()[i];
    //float *pParam = (float *)ports[nInputs + nOutputs + i];
    if (pParam)
    {
      IParam *param = GetParam(i);
      if(param->Value() != *pParam){
        param->Set(*pParam);
        // SendParameterValueFromAPI make no big sense for LV2, GUI is always separate
        OnParamChange(i, kHost);
      }
    }
  }
  LEAVE_PARAMS_MUTEX;
#endif

  // TODO: parameters
  // TODO: time info
  // TODO: midi

  ProcessBlock((iplug::sample**)inPorts, (iplug::sample**)outPorts, n_samples);
}

void IPlugLV2DSP::deactivate()
{
  OnActivate(false);
}


///////////////////////
// LV2 DSP Callbacks //
///////////////////////

static void c_connect_port(LV2_Handle instance, uint32_t port, void *data)
{
  (static_cast<IPlugLV2DSP*>(instance))->connect_port(port, data);
}

static void c_activate(LV2_Handle instance)
{
  (static_cast<IPlugLV2DSP*>(instance))->activate();
}

static void c_run(LV2_Handle instance, uint32_t n_samples)
{
  (static_cast<IPlugLV2DSP*>(instance))->run(n_samples);
}

static void c_deactivate(LV2_Handle instance)
{
  (static_cast<IPlugLV2DSP*>(instance))->deactivate();
}

static void c_cleanup(LV2_Handle instance)
{
  delete (static_cast<IPlugLV2DSP*>(instance));
}

static const void *c_extension_data(const char *uri)
{
  return nullptr;
}

static WDL_TypedBuf<LV2_Descriptor> sDescriptors;
// Static buffer for ALL URI strings.
// Instead of doing a bunch of small allocations, we do one large one.
static WDL_TypedBuf<char> sUriBuf;

const LV2_Descriptor*
IPlugLV2DSP::descriptor(uint32_t index, LV2_InstantiateFn instantiate)
{
  // Statically initialize the list of descriptors, one for each IO config.
  if (sDescriptors.GetSize() == 0)
  {
    WDL_PtrList<IOConfig> ioConfigs;
    int inChans, outChans, inBusses, outBusses;
    IPlugProcessor::ParseChannelIOStr(PLUG_CHANNEL_IO, ioConfigs, inChans, outChans, inBusses, outBusses);

    int nIOConfigs = ioConfigs.GetSize();
    // Allocate a buffer large enough for all URI strings.
    sUriBuf.Resize((strlen(PLUG_URI) + MAX_CONFIG_DIGITS + 6) * nIOConfigs);
    char* urip = sUriBuf.Get();
    char* uripEnd = urip + sUriBuf.GetSize();

    for (int i = 0; i < nIOConfigs; i++)
    {
      int uriLen = snprintf(urip, uripEnd - urip, "%s#io_%d", PLUG_URI, i);
      sDescriptors.Add(LV2_Descriptor {
        urip,
        instantiate,
        &c_connect_port,
        &c_activate,
        &c_run,
        &c_deactivate,
        &c_cleanup,
        &c_extension_data,
      });
      urip += uriLen;
    }
  }

  // Once everything is initialized returning descriptors is easy.
  if (index < sDescriptors.GetSize())
  {
    return sDescriptors.Get() + index;
  }
  else
  {
    return nullptr;
  }
}

#endif

#ifdef IPLUG_EDITOR

IPlugLV2Editor::IPlugLV2Editor(const InstanceInfo &info, const Config& config) : IPlugAPIBase(config, kAPILV2)
, mHostSupportIdle(false), mHostWidget(nullptr), mHostResize(nullptr)
{ 
  Trace(TRACELOC, "%s", config.pluginName);

  WDL_PtrList<IOConfig> IOConfigs;
  int totalNInChans, totalNOutChans;
  int totalNInBuses, totalNOutBuses;
  IPlugProcessor::ParseChannelIOStr(config.channelIOStr, IOConfigs, totalNInChans, totalNOutChans, totalNInBuses, totalNOutBuses);
  
  mParameterPortOffset = totalNInChans + totalNOutChans;

#ifdef OS_LINUX
  mEmbed = xcbt_embed_idle();
#endif
 
  mHostWrite      = info.write_function;
  mHostController = info.controller;

  auto features = info.features;
  if (features)
  {
    const LV2_Feature *feature;
    while((feature = *features++))
    {
      if(!strcmp(feature->URI, LV2_UI__parent))
      {
        mHostWidget = (LV2UI_Widget)feature->data;
      } else if(!strcmp(feature->URI, LV2_UI__idleInterface))
      {
        mHostSupportIdle = true;
      } else if(!strcmp(feature->URI, LV2_UI__resize))
      {
        mHostResize = (LV2UI_Resize *)feature->data;
      } else
      {
        // printf("Host feature: %s\n", feature->URI);
      }
    }
  }

     
  // TODO: CreateTimer();
}

LV2UI_Widget IPlugLV2Editor::CreateUI()
{
  // we can not do this in constructor, user code is not yet executed and so graphics can not be created
#ifdef OS_LINUX
  SetIntegration(mEmbed);
#endif

  auto widget = reinterpret_cast<LV2UI_Widget>(OpenWindow(mHostWidget));
  return widget;
}

IPlugLV2Editor::~IPlugLV2Editor()
{
  CloseWindow();

#ifdef OS_LINUX
  //xcbt_embed_dtor(mEmbed);
#endif
}

void IPlugLV2Editor::InformHostOfParamChange(int idx, double normalizedValue)
{
  // I use original (not normilized) value in LV2
  ENTER_PARAMS_MUTEX_STATIC;
  float value = GetParam(idx)->Value();
  LEAVE_PARAMS_MUTEX_STATIC;
  
  uint32_t port_index = mParameterPortOffset + idx;
  
  if (mHostWrite)
  {
    mHostWrite(mHostController, port_index, sizeof(float), 0, &value);
  }
}


void IPlugLV2Editor::port_event(uint32_t port_index, uint32_t buffer_size, uint32_t format, const void*  buffer)
{
  if ((format == 0) && (buffer_size == sizeof(float)) && buffer)
  {
    float value = *((float *)buffer);
    if (port_index >= mParameterPortOffset)
    {
      int idx = port_index - mParameterPortOffset;
      // printf("  Param %d = %f\n", idx, value);
      if (idx < NParams())
      {
        ENTER_PARAMS_MUTEX_STATIC;
        GetParam(idx)->Set(value);
        SendParameterValueFromDelegate(idx, value, false);
        OnParamChange(idx, kHost);
        LEAVE_PARAMS_MUTEX_STATIC;
      }
    }
  }
}

int IPlugLV2Editor::ui_idle()
{
  OnIdle();
#ifdef OS_LINUX
  xcbt_embed_idle_cb(mEmbed);
#endif
  return 0;
}

bool IPlugLV2Editor::EditorResizeFromUI(int viewWidth, int viewHeight, bool needsPlatformResize)
{
  if (mHostResize && needsPlatformResize)
  {
    return mHostResize->ui_resize(mHostResize->handle, viewWidth, viewHeight) == 0;
  }
  return false;
}


#endif

END_IPLUG_NAMESPACE
