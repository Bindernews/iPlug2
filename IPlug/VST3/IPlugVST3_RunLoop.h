/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/
#ifndef __IPLUGVST3_RUNLOOP
#define __IPLUGVST3_RUNLOOP

#include <memory>

#include "IPlugPlatform.h"

#include "IPlugTimer.h"

#include <ptrlist.h>
#include <functional>
#include "base/source/fobject.h"
#include "pluginterfaces/gui/iplugview.h"

BEGIN_IPLUG_NAMESPACE

struct VST3Timer;
struct EventHandler;
struct TimerHandler;

struct IPlugVST3_RunLoop final
{
public:
  using Self = IPlugVST3_RunLoop;

private:
  Steinberg::Linux::IRunLoop *runLoop;
  struct EventHandler* eHandler;
  bool eHandlerSet;
  struct TimerHandler* tHandler;
  bool tHandlerSet;

  WDL_PtrList<VST3Timer> mTimers;

  friend class EventHandler;
  friend class TimerHandler;

public:
  /** Create XCBT embed and IPlugVST3_RunLoop using VST3 IRunLoop interface
   * @param frame an object with IRunLoop interface
   * @return allocated embed structure in case the initialization could be done on nullptr*/
  static IPlugVST3_RunLoop* Create(Steinberg::FUnknown *frame);
  static void Destory(IPlugVST3_RunLoop* self);

  VST3Timer* CreateTimer(std::function<void()> callback, int msec);
  void DestroyTimer(VST3Timer* timer);
};

END_IPLUG_NAMESPACE

#endif
