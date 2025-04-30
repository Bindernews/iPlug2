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

int parse_config_index(const char *uri)
{
  size_t hashIndex = strcspn(uri, "#");
  if (uri[hashIndex] == 0) {
    return -1;
  }
  int ioIndex = 0;
  if (sscanf(uri + hashIndex, "io_%d", &ioIndex) != 1) {
    return -1;
  }
  return ioIndex;
}

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

#if IPLUG_DSP

IPlugLV2DSP::IPlugLV2DSP(const InstanceInfo &info, const Config& config)
  : IPlugAPIBase(config, kAPILV2)
  , IPlugProcessor(config, kAPILV2)
  , mFirstActivate(true)
  , mMap(nullptr)
{
  // maybe: info.descriptor should match our expectation, should we check that?

  Trace(TRACELOC, "%s", config.pluginName);

  // Allocate port pointers
  mPorts.Resize(2);
  mIOPorts.Resize( MaxNChannels(ERoute::kInput) + MaxNChannels(ERoute::kOutput) );
  mControlPorts.Resize( NParams() );

  SetSampleRate(info.rate);

  int block_size = DEFAULT_BLOCK_SIZE; // that can lead to allocation in RT, but there is no workaround in case host does not specify it

  bool validInstance = true;

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
      }
      else if(!strcmp(feature->URI, LV2_URID__map))
      {
        mMap = (LV2_URID_Map *)feature->data;
      }
      else if(!strcmp(feature->URI, LV2_URID__unmap))
      {
        // urid_unmap = (LV2_URID_Unmap *)feature->data;
      }
      else if (!strcmp(feature->URI, LV2_IPLUG2__InvalidInstance))
      {
        validInstance = false;
      }
    }
  }

  // If validInstance is false then we don't get URID map or anything like that. We use this so
  // we can get a plugin instance for the purpose of generating TTL files. When the InvalidInstance
  // feature is supplied, the plugin CANNOT be used. It WILL crash if you try to do almost anything.
  if (validInstance)
  {
    if(options) // options we are looking for are URID based
    {
      LV2_URID maxBlockLengthID = mMap->map(mMap->handle, LV2_BUF_SIZE__maxBlockLength);
      // maybe: sequenceSize
      for(; options->key ; ++options)
      {
        if((options->key == maxBlockLengthID) && (options->size == sizeof(int) && options->value))
        {
          block_size =  *(int *)options->value; // at least Arodour reports theoretical maximum here, not currently used buffer size
        }
      }
    }

    mURIs.init(mMap, NParams());
    mForgeCtrl.init(mMap);

    int config_index = parse_config_index(info.descriptor->URI);
    if (config_index != -1)
    {
      auto ioconfig = GetIOConfig(config_index);
      SetChannelConnections(ERoute::kInput, 0, ioconfig->GetTotalNChannels(ERoute::kInput), true);
      SetChannelConnections(ERoute::kOutput, 0, ioconfig->GetTotalNChannels(ERoute::kOutput), true);
    }

    SetBlockSize(block_size);
  }
  else
  {
    SetChannelConnections(ERoute::kInput, 0, MaxNChannels(ERoute::kInput), false);
    SetChannelConnections(ERoute::kOutput, 0, MaxNChannels(ERoute::kOutput), false);
  }


  // TODO: CreateTimer();
}

IPlugLV2DSP::~IPlugLV2DSP()
{
}

//IPlugProcessor
bool IPlugLV2DSP::SendMidiMsg(const IMidiMsg& msg)
{
  SendMidiMsgFromUI(msg);
  return true;
}

// IPlugAPIBase
void IPlugLV2DSP::SendMidiMsgFromUI(const IMidiMsg &msg)
{
  LV2_Atom atmidi = { 3, mURIs.midi_MidiEvent };
  uint8_t buf[3] = { msg.mStatus, msg.mData1, msg.mData2 };

  if (0 == lv2_atom_forge_frame_time(mForgeCtrl, msg.mOffset)) return;
  if (!mForgeCtrl.forge_raw(&atmidi, sizeof(LV2_Atom))) return;
  if (!mForgeCtrl.forge_raw(buf, 3)) return;
  lv2_atom_forge_pad(mForgeCtrl, sizeof(LV2_Atom) + atmidi.size);
}

void IPlugLV2DSP::SendSysexMsgFromUI(const ISysEx &msg)
{
  LV2_Atom atom = { (uint32_t)msg.mSize, mURIs.midi_MidiEvent };
  if (0 == lv2_atom_forge_frame_time(mForgeCtrl, msg.mOffset)) return;
  if (!mForgeCtrl.forge_raw(&atom, sizeof(LV2_Atom))) return;
  if (!mForgeCtrl.forge_raw(msg.mData, atom.size)) return;
  lv2_atom_forge_pad(mForgeCtrl, sizeof(LV2_Atom) + atom.size);
}

void IPlugLV2DSP::SendArbitraryMsgFromUI(int msgTag, int ctrlTag = kNoTag, int dataSize = 0, const void* pData = nullptr)
{
  LV2_Atom_Forge_Frame frame;
  lv2_atom_forge_frame_time(mForgeCtrl, 0);
  lv2_atom_forge_object(mForgeCtrl, &frame, 0, mURIs.iplug2_UIMessage);
  lv2_atom_forge_key(mForgeCtrl, mURIs.iplug2_msgTag);
  lv2_atom_forge_int(mForgeCtrl, msgTag);
  lv2_atom_forge_key(mForgeCtrl, mURIs.iplug2_ctrlTag);
  lv2_atom_forge_int(mForgeCtrl, ctrlTag);
  lv2_atom_forge_key(mForgeCtrl, mURIs.iplug2_data);
  // Chunk
  lv2_atom_forge_atom(mForgeCtrl, dataSize, mURIs.atom_Chunk);
  lv2_atom_forge_raw(mForgeCtrl, pData, dataSize);
  lv2_atom_forge_pad(mForgeCtrl, dataSize);
  // Finish
  lv2_atom_forge_pop(mForgeCtrl, &frame);
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

  // Initialize output sequences
  mForgeCtrl.open(static_cast<LV2_Atom_Sequence*>(ports[1]));

  AttachBuffers(ERoute::kInput, 0, nInputs, inPorts, n_samples);
  AttachBuffers(ERoute::kOutput, 0, nOutputs, outPorts, n_samples);

  LV2_ATOM_SEQUENCE_FOREACH(static_cast<LV2_Atom_Sequence*>(ports[0]), ev)
  {
    uint32_t atom_type = ev->body.type;

    if (atom_type == mURIs.atom_Object)
    {
      const LV2_Atom_Object* obj = (LV2_Atom_Object*)&ev->body;
      // Handle patch messages
      if (obj->body.otype == mURIs.patch_Set)
      {
        uint32_t sampleAt = 0;
        // We should check to make sure bad hosts don't do this.
        // If so, report to host.
        if (ev->time.frames < 0 || ev->time.frames > n_samples)
        {
          sampleAt = n_samples - 1;
        }
        else
        {
          sampleAt = (uint32_t)ev->time.frames;
        }
        HandleAtomPatchSet(obj, EParamSource::kHost, sampleAt);
      }

      // Handle arbitrary messages from the UI
      if (obj->body.otype == mURIs.iplug2_UIMessage)
      {
        HandleAtomUIMessage(obj);
      }
    }

    // Handle MIDI messages
    if (atom_type == mURIs.midi_MidiEvent)
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

  mForgeCtrl.close();
}

void IPlugLV2DSP::deactivate()
{
  OnActivate(false);
}


// Private methods

///////////////////////
// LV2 DSP Callbacks //
///////////////////////

extern "C" {
  // This MUST be extern C with the name "lv2_descriptor"
  LV2_SYMBOL_EXPORT const LV2_Descriptor* lv2_descriptor(uint32_t index)
  {
    return IPlugLV2DSP::descriptor(index);
  }
}

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


LV2_Handle IPlugLV2DSP::instantiate_fn(
  const LV2_Descriptor *descriptor, double rate, const char* bundle_path, const LV2_Feature* const* features)
{
  struct InstanceInfo info = { descriptor, rate, bundle_path, features };
  IPlugLV2DSP *instance = MakePlug(info);
  return static_cast<LV2_Handle>(instance);
}

static WDL_TypedBuf<LV2_Descriptor> sDescriptors;
// Static buffer for ALL URI strings.
// Instead of doing a bunch of small allocations, we do one large one. Why? Because it's easy and efficient.
static WDL_TypedBuf<char> sUriBuf;

const LV2_Descriptor*
IPlugLV2DSP::descriptor(uint32_t index)
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
        &instantiate_fn,
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

#endif // IPLUG_DSP

#if IPLUG_EDITOR
// See IPlugLV2Editor.cpp
#endif // IPLUG_EDITOR


/////////////////
// Common Code //
/////////////////
#pragma region Common Code

AtomSequenceForge::AtomSequenceForge()
{}

AtomSequenceForge::~AtomSequenceForge()
{}

void AtomSequenceForge::init(LV2_URID_Map *map)
{
  lv2_atom_forge_init(&forge, map);
  used = false;
}

void AtomSequenceForge::open(LV2_Atom_Sequence *seq)
{
  if (!used)
  {
    used = true;
    lv2_atom_forge_set_buffer(&forge, (uint8_t*)seq, seq->atom.size);
    lv2_atom_forge_sequence_head(&forge, &sequence_head, 0);
  }
}

void AtomSequenceForge::close()
{
  if (used)
  {
    used = false;
    lv2_atom_forge_pop(&forge, &sequence_head);
  }
}

bool AtomSequenceForge::forge_raw(const void *data, uint32_t size)
{
  return lv2_atom_forge_raw(&forge, data, size) != 0;
}

bool URIDMap::init(LV2_URID_Map *map, int nParams)
{
  mMap = map;

  // Find-Replace regex to turn name into full line
  // ([a-z]+)_([A-Za-z]+)   this->$1_$2 = GET_URID(LV2_\U$1 __$2);
#define GET_URID(key, name) this->key = mMap->map(mMap->handle, name); if (this->key == 0) { return false; }
  GET_URID(atom_atomTransfer,    LV2_ATOM__atomTransfer);
  GET_URID(atom_Blank,           LV2_ATOM__Blank);
  GET_URID(atom_Chunk,           LV2_ATOM__Chunk);
  GET_URID(atom_eventTransfer,   LV2_ATOM__eventTransfer);
  GET_URID(atom_Object,          LV2_ATOM__Object);
  GET_URID(atom_URID,            LV2_ATOM__URID);
  GET_URID(atom_Float,           LV2_ATOM__Float);
  GET_URID(atom_Bool,            LV2_ATOM__Bool);
  GET_URID(midi_MidiEvent,       LV2_MIDI__MidiEvent);
  GET_URID(patch_Set,            LV2_PATCH__Set);
  GET_URID(patch_property,       LV2_PATCH__property);
  GET_URID(patch_value,          LV2_PATCH__value);
  GET_URID(iplug2_ctrlTag,       LV2_IPLUG2__ctrlTag);
  GET_URID(iplug2_data,          LV2_IPLUG2__data);
  GET_URID(iplug2_msgTag,        LV2_IPLUG2__msgTag);
  GET_URID(iplug2_UIMessage,     LV2_IPLUG2__UIMessage);
#undef GET_URID

  // Map all params to URIDs
  WDL_String uri;
  for (int n = 0; n < nParams; n++)
  {
    uri.SetFormatted(2048, "%s#Patch_%d", PLUG_URI, n);
    get(uri.Get());
    uri.SetFormatted(2048, "%s#port_param_%d", PLUG_URI, n);
    get(uri.Get());
  }

  return true;
}

int URIDMap::getParam(LV2_URID urid)
{
  auto it = mParamMap.find(urid);
  if (it != mParamMap.end()) {
    return it->second;
  } else {
    return -1;
  }
}

LV2_URID URIDMap::get(const char *uri)
{
  auto it = mExtras.find(uri);
  if (it == mExtras.end()) {
    LV2_URID urid = mMap->map(mMap->handle, uri);
    mExtras[uri] = urid;
    return urid;
  } else {
    return it->second;
  }
}

#pragma endregion Common Code

END_IPLUG_NAMESPACE
