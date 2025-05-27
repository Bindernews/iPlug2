#undef IPLUG_DSP
#include "IPlugLV2.h"
#include "lv2/core/lv2.h"

using namespace iplug;

IPlugLV2Editor::IPlugLV2Editor(const InstanceInfo &info, const Config& config) : IPlugAPIBase(config, kAPILV2)
, mHostSupportIdle(false), mHostWidget(nullptr), mHostResize(nullptr)
{
  Trace(TRACELOC, "%s", config.pluginName);

  WDL_PtrList<IOConfig> IOConfigs;
  int totalNInChans, totalNOutChans;
  int totalNInBuses, totalNOutBuses;
  IPlugProcessor::ParseChannelIOStr(config.channelIOStr, IOConfigs, totalNInChans, totalNOutChans, totalNInBuses, totalNOutBuses);

  mParameterPortOffset = totalNInChans + totalNOutChans;

  mHostWrite      = info.write_function;
  mHostController = info.controller;

  auto features = info.features;
  if (features)
  {
    const LV2_Feature *feature;
    while((feature = *features++))
    {
      if (!strcmp(feature->URI, LV2_URID__map))
      {
        mURIs.init((LV2_URID_Map*)feature->data, 0);
      }
      if(!strcmp(feature->URI, LV2_UI__parent))
      {
        mHostWidget = (LV2UI_Widget)feature->data;
      }
      else if(!strcmp(feature->URI, LV2_UI__idleInterface))
      {
        mHostSupportIdle = true;
      }
      else if(!strcmp(feature->URI, LV2_UI__resize))
      {
        mHostResize = (LV2UI_Resize *)feature->data;
      }
      else
      {
        // printf("Host feature: %s\n", feature->URI);
      }
    }
  }


  // TODO: CreateTimer();
}

LV2UI_Widget IPlugLV2Editor::CreateUI()
{
  auto widget = reinterpret_cast<LV2UI_Widget>(OpenWindow(mHostWidget));
  return widget;
}

IPlugLV2Editor::~IPlugLV2Editor()
{
  CloseWindow();
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
#ifdef LV2_CONTROL_PORTS
  // This is for control ports
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
#endif

  // Listening for output messages from the control_out port
  if (port_index == 1 && format == mURIs.atom_eventTransfer)
  {
    auto atom = reinterpret_cast<const LV2_Atom*>(buffer);

    if (atom->type == mURIs.atom_Object)
    {
      const LV2_Atom_Object* obj = reinterpret_cast<const LV2_Atom_Object*>(((const uint8_t*)buffer) + sizeof(LV2_Atom));
      // Handle patch messages
      if (obj->body.otype == mURIs.patch_Set)
      {
        // We don't get frame times so sampleAt = 0
        HandleAtomPatchSet(obj, EParamSource::kHost, 0);
      }

      // Handle arbitrary messages from the UI
      if (obj->body.otype == mURIs.iplug2_UIMessage)
      {
        HandleAtomUIMessage(obj);
      }
    }

    // Handle MIDI messages
    if (atom->type == mURIs.midi_MidiEvent)
    {
      /*
      const uint8_t* const msg = (const uint8_t*)(ev + 1);
      switch (lv2_midi_message_type(msg))
      {
      case LV2_MIDI_MSG_NOTE_ON:
      case LV2_MIDI_MSG_NOTE_OFF:
        ProcessMidiMsg(IMidiMsg((int)(ev->time.frames), msg[0], msg[1], msg[2]));
        break;
      // TODO finish switch-case for processing MIDI messages
      }
      */
    }
  }

}

int IPlugLV2Editor::ui_idle()
{
  OnIdle();

  // Return 0 if the UI is still open
  if (GetUI() != nullptr) {
    return 0;
  } else {
    return 1;
  }
}

int IPlugLV2Editor::ui_resize(int width, int height)
{
  SetEditorSize(width, height);
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

static LV2UI_Handle ui_instantiate(
  const LV2UI_Descriptor*   descriptor,
  const char*               plugin_uri,
  const char*               bundle_path,
  LV2UI_Write_Function      write_function,
  LV2UI_Controller          controller,
  LV2UI_Widget*             widget,
  const LV2_Feature* const* features)
{
  struct InstanceInfo info = { descriptor, plugin_uri, bundle_path, write_function, controller, features };
  IPlugLV2Editor *instance = MakePlug(info);
  *widget = instance->CreateUI();
  return static_cast<LV2UI_Handle>(instance);
}

static void ui_cleanup(LV2UI_Handle instance)
{
  delete (static_cast<IPlugLV2Editor*>(instance));
}

static void ui_port_event(LV2UI_Handle instance, uint32_t port_index, uint32_t buffer_size, uint32_t format, const void*  buffer)
{
  (static_cast<IPlugLV2Editor*>(instance))->port_event(port_index, buffer_size, format, buffer);
}

static int ui_idle(LV2UI_Handle instance)
{
  return (static_cast<IPlugLV2Editor*>(instance))->ui_idle();
}

static int ui_show(LV2UI_Handle instance)
{
  // TODO show UI
  return (static_cast<IPlugLV2Editor*>(instance))->ui_idle();
}

static int ui_hide(LV2UI_Handle instance)
{
  // TODO hide UI
  return (static_cast<IPlugLV2Editor*>(instance))->ui_idle();
}

static int ui_resize(LV2UI_Feature_Handle handle, int width, int height)
{
  return static_cast<IPlugLV2Editor*>(handle)->ui_resize(width, height);
}

static const void *ui_extension_data(const char *uri)
{
  static const LV2UI_Idle_Interface idle = { ui_idle };
  static const LV2UI_Resize ext_resize = { NULL, ui_resize };
  //static const LV2UI_Show_Interface uiShow = { ui_show, ui_hide };

  if (!strcmp(uri, LV2_UI__idleInterface))
  {
    return &idle;
  }
  else if (!strcmp(uri, LV2_UI__resize))
  {
    return &ext_resize;
  }
  // if (strcmp(uri, LV2_UI__showInterface) == 0)
  // {
  //   return &uiShow;
  // }
  return nullptr;
}

static const LV2UI_Descriptor ui_descriptor =
{
  PLUG_UI_URI,
  ui_instantiate,
  ui_cleanup,
  ui_port_event,
  ui_extension_data
};

LV2_SYMBOL_EXPORT const LV2UI_Descriptor* lv2ui_descriptor(uint32_t index)
{
        switch (index) {
        case 0:
                return &ui_descriptor;
        default:
                return NULL;
        }
}



